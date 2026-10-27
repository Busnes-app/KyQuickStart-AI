package tlsprofile

import (
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

type countedListener struct {
	net.Listener
	accepted atomic.Int32
}

func (l *countedListener) Accept() (net.Conn, error) {
	c, e := l.Listener.Accept()
	if e == nil {
		l.accepted.Add(1)
	}
	return c, e
}

// The launcher probe deliberately exposes no writable Kubernetes API. It proves
// whether an administrative request crosses TLS, while test/kube.sh owns actual
// ServiceAccount/RBAC convergence and revocation on a disposable cluster.
func TestKubernetesTLSProfile(t *testing.T) {
	binary := os.Getenv("KYQS_TEST_KUBECTL")
	if binary == "" {
		t.Fatal("set KYQS_TEST_KUBECTL to the exact client executable")
	}
	binary, err := filepath.Abs(binary)
	if err != nil {
		t.Fatal(err)
	}
	root, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	operations := []string{"helper", "launcher"}
	if os.Getenv("KYQS_TEST_BASELINE") == "1" {
		operations = []string{"launcher"}
	}
	for _, tc := range []struct {
		where string
		bits  int
	}{{"leaf", 1024}, {"leaf", 2047}, {"root", 1024}, {"root", 2047}, {"intermediate", 1024}, {"intermediate", 2047}, {"leaf", 2048}, {"leaf", 0}, {"hostname", 0}, {"untrusted", 0}, {"expired", 0}} {
		t.Run(fmt.Sprintf("%s-%d", tc.where, tc.bits), func(t *testing.T) {
			ip := net.ParseIP("127.0.0.1")
			if tc.where == "hostname" {
				ip = net.ParseIP("127.0.0.2")
			}
			certificate, ca := openSSFTLSCertificate(t, ip, tc.where, tc.bits)
			if tc.where == "untrusted" {
				_, ca = openSSFTLSCertificate(t, ip, "leaf", 0)
			}
			var requests atomic.Int32
			srv := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") != "Bearer disposable-public-probe-token" {
					t.Errorf("wrong fixture credential")
				}
				requests.Add(1)
				if r.URL.Path != "/version" {
					http.Error(w, "fixture has no Kubernetes resources", http.StatusNotFound)
					return
				}
				w.Header().Set("Content-Type", "application/json")
				io.WriteString(w, `{"major":"1","minor":"37","gitVersion":"v1.37.0"}`)
			}))
			listener := &countedListener{Listener: srv.Listener}
			srv.Listener = listener
			srv.TLS = &tls.Config{Certificates: []tls.Certificate{certificate}, MinVersion: tls.VersionTLS12}
			srv.Config.ErrorLog = log.New(io.Discard, "", 0)
			srv.StartTLS()
			defer srv.Close()
			cfg := map[string]any{"apiVersion": "v1", "kind": "Config", "current-context": "probe", "clusters": []any{map[string]any{"name": "probe", "cluster": map[string]any{"server": srv.URL, "certificate-authority-data": base64.StdEncoding.EncodeToString(ca)}}}, "contexts": []any{map[string]any{"name": "probe", "context": map[string]any{"cluster": "probe", "user": "probe"}}}, "users": []any{map[string]any{"name": "probe", "user": map[string]any{"token": "disposable-public-probe-token"}}}}
			raw, err := json.Marshal(cfg)
			if err != nil {
				t.Fatal(err)
			}
			home := t.TempDir()
			file := filepath.Join(home, "kubeconfig.json")
			if err = os.WriteFile(file, raw, 0600); err != nil {
				t.Fatal(err)
			}
			tools := filepath.Join(home, "tools")
			if err = os.Mkdir(tools, 0700); err != nil {
				t.Fatal(err)
			}
			if err = os.Symlink(binary, filepath.Join(tools, "kubectl")); err != nil {
				t.Fatal(err)
			}
			stub := filepath.Join(tools, "kyquickstart")
			if err = os.WriteFile(stub, []byte("#!/bin/sh\necho 0.0.0-fixture\n"), 0700); err != nil {
				t.Fatal(err)
			}
			good := tc.where != "hostname" && tc.where != "untrusted" && tc.where != "expired"
			for _, operation := range operations {
				for _, mode := range []string{"0", "1"} {
					requests.Store(0)
					listener.accepted.Store(0)
					ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
					args := []string{"--kubeconfig", file, "--request-timeout=5s", "get", "--raw=/version"}
					command := filepath.Join(root, "bin/kubectl-policy")
					if operation == "launcher" {
						command = filepath.Join(root, "kyqs-ai")
						args = []string{"add-cluster", "fixture", file}
					}
					cmd := exec.CommandContext(ctx, command, args...)
					cmd.WaitDelay = 2 * time.Second
					cmd.Env = []string{"PATH=" + tools + string(os.PathListSeparator) + os.Getenv("PATH"), "HOME=" + home, "XDG_STATE_HOME=" + filepath.Join(home, "state"), "GODEBUG=fips140=off", "KYQS_STRONG_KUBE_TLS=" + mode, "KYQS_KYQUICKSTART=" + stub}
					output, err := cmd.CombinedOutput()
					expired := ctx.Err() != nil
					cancel()
					if expired {
						t.Fatalf("operation=%s timed out: %s", operation, output)
					}
					want := good && (mode == "0" || tc.bits == 0 || tc.bits >= 2048)
					if operation == "helper" && (err == nil) != want {
						t.Fatalf("profile=%s helper exit=%v want success=%v: %s", mode, err, want, output)
					}
					if (requests.Load() > 0) != want {
						t.Fatalf("operation=%s profile=%s administrative HTTP=%d want HTTP=%v: %s", operation, mode, requests.Load(), want, output)
					}
					if listener.accepted.Load() == 0 {
						t.Fatalf("operation=%s profile=%s did not reach listener: %s", operation, mode, output)
					}
					t.Logf("operation=%s profile=%s HTTP=%d TCP=%d", operation, mode, requests.Load(), listener.accepted.Load())
				}
			}
		})
	}
}

func openSSFTLSCertificate(t *testing.T, ip net.IP, weakAt string, bits int) (tls.Certificate, []byte) {
	t.Helper()
	var issuer *x509.Certificate
	var issuerKey crypto.Signer
	var chain [][]byte
	var ca []byte
	var leafKey crypto.Signer
	for i, name := range []string{"root", "intermediate", "leaf"} {
		var key crypto.Signer
		var err error
		if name == weakAt && bits != 0 {
			key, err = rsa.GenerateKey(rand.Reader, bits)
		} else {
			key, err = ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		}
		if err != nil {
			t.Fatal(err)
		}
		cert := &x509.Certificate{SerialNumber: big.NewInt(int64(i + 1)), Subject: pkix.Name{CommonName: "disposable Kubernetes " + name}, NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour), BasicConstraintsValid: true, IsCA: name != "leaf", KeyUsage: x509.KeyUsageDigitalSignature}
		if name == "leaf" && weakAt == "expired" {
			cert.NotBefore = time.Now().Add(-3 * time.Hour)
			cert.NotAfter = time.Now().Add(-2 * time.Hour)
		}
		if cert.IsCA {
			cert.KeyUsage |= x509.KeyUsageCertSign
		} else {
			cert.IPAddresses = []net.IP{ip}
			cert.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}
			leafKey = key
		}
		parent, signer := issuer, issuerKey
		if i == 0 {
			parent, signer = cert, key
		}
		der, err := x509.CreateCertificate(rand.Reader, cert, parent, key.Public(), signer)
		if err != nil {
			t.Fatal(err)
		}
		issuer, err = x509.ParseCertificate(der)
		if err != nil {
			t.Fatal(err)
		}
		issuerKey = key
		if i == 0 {
			ca = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
		} else {
			chain = append([][]byte{der}, chain...)
		}
	}
	return tls.Certificate{Certificate: chain, PrivateKey: leafKey}, ca
}
