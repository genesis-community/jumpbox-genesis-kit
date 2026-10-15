package spec_test

import (
	"os"
	"path/filepath"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

const usersBase = "secret/test/jumpbox/openvpn/certs/users/"

// certVault builds a fake vault with the named VPN user certificates listed.
// Only the names in live have a readable certificate.
func certVault(listed, live []string) string {
	dir := registry(nil, nil)

	var paths []string
	for _, name := range listed {
		paths = append(paths, usersBase+name)
	}
	Expect(os.WriteFile(filepath.Join(dir, "paths"), []byte(strings.Join(paths, "\n")+"\n"), 0o644)).To(Succeed())

	for _, name := range live {
		secret := filepath.Join(dir, "live", usersBase, name)
		Expect(os.MkdirAll(secret, 0o755)).To(Succeed())
		Expect(os.WriteFile(filepath.Join(secret, "certificate"), []byte("pem\n"), 0o644)).To(Succeed())
	}
	return dir
}

func calls(dir string) string {
	data, err := os.ReadFile(filepath.Join(dir, "calls"))
	if os.IsNotExist(err) {
		return ""
	}
	Expect(err).ToNot(HaveOccurred())
	return string(data)
}

var _ = Describe("the certificate addons", func() {
	for _, addon := range []string{"certs", "renew-all-certs"} {
		addon := addon

		Describe(addon, func() {
			It("skips a certificate that was revoked", func() {
				dir := certVault([]string{"alice", "bob"}, []string{"alice"})
				out, err := runHelper(dir, "cert-addon.pl", addon)
				Expect(err).ToNot(HaveOccurred(), out)
				Expect(calls(dir)).To(ContainSubstring(usersBase + "alice"))
				Expect(calls(dir)).ToNot(ContainSubstring(usersBase + "bob"))
			})

			It("stops and names the certificate when the vault returns an error", func() {
				dir := certVault([]string{"alice", "bob"}, []string{"alice", "bob"})
				Expect(os.WriteFile(filepath.Join(dir, "errors"), []byte(usersBase+"bob\n"), 0o644)).To(Succeed())
				out, err := runHelper(dir, "cert-addon.pl", addon)
				Expect(err).To(HaveOccurred())
				Expect(out).To(ContainSubstring(usersBase + "bob:certificate"))
			})
		})
	}
})
