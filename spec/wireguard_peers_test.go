package spec_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	. "github.com/genesis-community/testkit/v2/testing"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

const peersBase = "secret/test/jumpbox/wireguard/peers/"

// registry builds a fake vault in a temporary directory. Every name in listed
// shows up in `safe paths`, and every name in live also has readable keys.
func registry(listed, live []string) string {
	dir := GinkgoT().TempDir()

	var paths []string
	for _, name := range listed {
		paths = append(paths, peersBase+name)
	}
	Expect(os.WriteFile(filepath.Join(dir, "paths"), []byte(strings.Join(paths, "\n")+"\n"), 0o644)).To(Succeed())

	for _, name := range live {
		secret := filepath.Join(dir, "live", peersBase, name)
		Expect(os.MkdirAll(secret, 0o755)).To(Succeed())
		for key, value := range map[string]string{
			"public": "pub-" + name, "psk": "psk-" + name, "allowed_ips": "10.20.31.0/24",
		} {
			Expect(os.WriteFile(filepath.Join(secret, key), []byte(value+"\n"), 0o644)).To(Succeed())
		}
	}
	return dir
}

// peers runs the registry helper against the fake vault and returns its output.
func peers(dir, mode string) string {
	support := filepath.Join(KitDir, "spec", "support")
	cmd := exec.Command("perl", filepath.Join(support, "wireguard-peers.pl"), mode)
	cmd.Env = append(os.Environ(),
		"PATH="+support+string(os.PathListSeparator)+os.Getenv("PATH"),
		"FAKE_SAFE_DIR="+dir,
	)
	out, err := cmd.CombinedOutput()
	Expect(err).ToNot(HaveOccurred(), string(out))
	return string(out)
}

var _ = Describe("the wireguard peer registry", func() {
	It("lists the peers that are registered", func() {
		dir := registry([]string{"laptop", "phone"}, []string{"laptop", "phone"})
		Expect(peers(dir, "list")).To(Equal("laptop\nphone\n"))
	})

	It("ignores a peer that safe still lists after it was moved away", func() {
		dir := registry([]string{"laptop", "gone"}, []string{"laptop"})
		Expect(peers(dir, "list")).To(Equal("laptop\n"))
	})

	It("renders a fragment that leaves out a peer that was moved away", func() {
		dir := registry([]string{"laptop", "gone"}, []string{"laptop"})
		fragment := peers(dir, "fragment")
		Expect(fragment).To(ContainSubstring("name: laptop"))
		Expect(fragment).ToNot(ContainSubstring("gone"))
	})

	It("renders nothing when every listed peer was moved away", func() {
		dir := registry([]string{"gone"}, nil)
		Expect(peers(dir, "fragment")).To(Equal("(none)\n"))
	})
})
