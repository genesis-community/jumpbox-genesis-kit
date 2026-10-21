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

// runHelper runs a Perl helper from spec/support against the fake vault and
// returns its combined output with the error from the process, if any.
func runHelper(dir, script string, args ...string) (string, error) {
	support := filepath.Join(KitDir, "spec", "support")
	cmd := exec.Command("perl", append([]string{filepath.Join(support, script)}, args...)...)
	cmd.Env = append(os.Environ(),
		"PATH="+support+string(os.PathListSeparator)+os.Getenv("PATH"),
		"FAKE_SAFE_DIR="+dir,
	)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// peers runs the registry helper against the fake vault and returns its output.
func peers(dir string, args ...string) string {
	out, err := runHelper(dir, "wireguard-peers.pl", args...)
	Expect(err).ToNot(HaveOccurred(), out)
	return out
}

// sealVault makes `safe exists` fail for the named peers, as a sealed vault does.
func sealVault(dir string, names ...string) {
	var secrets []string
	for _, name := range names {
		secrets = append(secrets, peersBase+name)
	}
	Expect(os.WriteFile(filepath.Join(dir, "errors"), []byte(strings.Join(secrets, "\n")+"\n"), 0o644)).To(Succeed())
}

// failListing makes `safe paths` fail with the given message on stderr.
func failListing(dir, msg string) {
	Expect(os.WriteFile(filepath.Join(dir, "paths-error"), []byte(msg+"\n"), 0o644)).To(Succeed())
}

// listedPaths returns the paths that `safe paths` would list in the fake vault.
func listedPaths(dir string) string {
	data, err := os.ReadFile(filepath.Join(dir, "paths"))
	Expect(err).ToNot(HaveOccurred())
	return string(data)
}

// removePeer runs the remove-peer addon against the fake vault.
func removePeer(dir, name string) (string, error) {
	return runHelper(dir, "wireguard-addon.pl", "remove-peer", name)
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

	Context("when the vault returns an error instead of an answer", func() {
		It("reports a secret that is missing as missing", func() {
			dir := registry([]string{"gone"}, nil)
			Expect(peers(dir, "has", peersBase+"gone:public")).To(Equal("no\n"))
		})

		It("reports a secret that is present as present", func() {
			dir := registry([]string{"laptop"}, []string{"laptop"})
			Expect(peers(dir, "has", peersBase+"laptop:public")).To(Equal("yes\n"))
		})

		It("fails and names the path instead of reporting the secret as missing", func() {
			dir := registry([]string{"laptop"}, []string{"laptop"})
			sealVault(dir, "laptop")
			out, err := runHelper(dir, "wireguard-peers.pl", "has", peersBase+"laptop:public")
			Expect(err).To(HaveOccurred())
			Expect(out).To(ContainSubstring(peersBase + "laptop:public"))
			Expect(out).To(ContainSubstring("Sealed"))
		})

		It("does not drop a peer from the list", func() {
			dir := registry([]string{"laptop", "phone"}, []string{"laptop", "phone"})
			sealVault(dir, "phone")
			out, err := runHelper(dir, "wireguard-peers.pl", "list")
			Expect(err).To(HaveOccurred())
			Expect(out).To(ContainSubstring("phone"))
		})

		It("does not render a manifest without the peer", func() {
			dir := registry([]string{"laptop", "phone"}, []string{"laptop", "phone"})
			sealVault(dir, "phone")
			_, err := runHelper(dir, "wireguard-peers.pl", "fragment")
			Expect(err).To(HaveOccurred())
		})

		It("does not hand out the address of a peer it could not read", func() {
			dir := registry([]string{"laptop"}, []string{"laptop"})
			sealVault(dir, "laptop")
			_, err := runHelper(dir, "wireguard-peers.pl", "alloc", "10.20.31.0/24")
			Expect(err).To(HaveOccurred())
		})
	})

	Context("when the vault cannot list the registry", func() {
		It("reads an empty registry as having no peers", func() {
			dir := registry(nil, nil)
			failListing(dir, "!! no secret exists at "+peersBase)
			Expect(peers(dir, "list")).To(Equal(""))
			Expect(peers(dir, "fragment")).To(Equal("(none)\n"))
		})

		It("fails and names the registry instead of reporting no peers", func() {
			dir := registry([]string{"laptop"}, []string{"laptop"})
			failListing(dir, "!! 403 permission denied")
			out, err := runHelper(dir, "wireguard-peers.pl", "list")
			Expect(err).To(HaveOccurred())
			Expect(out).To(ContainSubstring(peersBase))
			Expect(out).To(ContainSubstring("permission denied"))
		})

		It("does not render a manifest without the peers", func() {
			dir := registry([]string{"laptop"}, []string{"laptop"})
			failListing(dir, "!! 503 Sealed: Vault is sealed")
			out, err := runHelper(dir, "wireguard-peers.pl", "fragment")
			Expect(err).To(HaveOccurred())
			Expect(out).ToNot(ContainSubstring("(none)"))
		})

		It("does not hand out an address that a peer may hold", func() {
			dir := registry([]string{"laptop"}, []string{"laptop"})
			failListing(dir, "!! 503 Sealed: Vault is sealed")
			_, err := runHelper(dir, "wireguard-peers.pl", "alloc", "10.20.31.0/24")
			Expect(err).To(HaveOccurred())
		})

		It("does not let remove-peer treat a name as unregistered", func() {
			dir := registry([]string{"gone"}, nil)
			failListing(dir, "!! 503 Sealed: Vault is sealed")
			out, err := removePeer(dir, "gone")
			Expect(err).To(HaveOccurred())
			Expect(out).To(ContainSubstring("could not be listed"))
			Expect(out).ToNot(ContainSubstring("is not registered"))
			Expect(listedPaths(dir)).To(ContainSubstring(peersBase + "gone"))
		})
	})
})

var _ = Describe("the remove-peer addon", func() {
	It("archives the peer and destroys its registry entry", func() {
		dir := registry([]string{"laptop", "phone"}, []string{"laptop", "phone"})
		out, err := removePeer(dir, "laptop")
		Expect(err).ToNot(HaveOccurred(), out)

		Expect(calls(dir)).To(MatchRegexp(`mv ` + peersBase + `laptop secret/test/jumpbox/wireguard/revoked/laptop-\d+\n`))
		Expect(calls(dir)).To(ContainSubstring("delete --force --destroy --all " + peersBase + "laptop\n"))
		Expect(listedPaths(dir)).ToNot(ContainSubstring(peersBase + "laptop\n"))
		Expect(listedPaths(dir)).To(MatchRegexp(`secret/test/jumpbox/wireguard/revoked/laptop-\d+`))

		revoked, err := filepath.Glob(filepath.Join(dir, "live", "secret/test/jumpbox/wireguard/revoked", "laptop-*", "public"))
		Expect(err).ToNot(HaveOccurred())
		Expect(revoked).To(HaveLen(1))
	})

	It("leaves the next deploy with only the remaining peers", func() {
		dir := registry([]string{"laptop", "phone"}, []string{"laptop", "phone"})
		out, err := removePeer(dir, "laptop")
		Expect(err).ToNot(HaveOccurred(), out)

		Expect(peers(dir, "list")).To(Equal("phone\n"))
		fragment := peers(dir, "fragment")
		Expect(fragment).To(ContainSubstring("name: phone"))
		Expect(fragment).ToNot(ContainSubstring("laptop"))

		out, err = removePeer(dir, "laptop")
		Expect(err).To(HaveOccurred())
		Expect(out).To(ContainSubstring("Peer 'laptop' is not registered"))
	})

	It("warns and still revokes the peer when the entry cannot be destroyed", func() {
		dir := registry([]string{"laptop", "phone"}, []string{"laptop", "phone"})
		Expect(os.WriteFile(filepath.Join(dir, "delete-error"), []byte("!! 403 permission denied\n"), 0o644)).To(Succeed())
		out, err := removePeer(dir, "laptop")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(ContainSubstring("could not be destroyed"))
		Expect(out).To(ContainSubstring("permission denied"))
		Expect(out).To(ContainSubstring("safe delete --force --destroy --all " + peersBase + "laptop"))

		Expect(listedPaths(dir)).To(ContainSubstring(peersBase + "laptop\n"))
		Expect(peers(dir, "list")).To(Equal("phone\n"))
		Expect(peers(dir, "fragment")).ToNot(ContainSubstring("laptop"))
	})

	It("destroys a soft-deleted empty entry that an older remove-peer left behind", func() {
		dir := registry([]string{"laptop", "gone"}, []string{"laptop"})
		out, err := removePeer(dir, "gone")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(out).To(ContainSubstring("had no data"))
		Expect(calls(dir)).ToNot(ContainSubstring("mv "))
		Expect(calls(dir)).To(ContainSubstring("delete --force --destroy --all " + peersBase + "gone\n"))
		Expect(listedPaths(dir)).ToNot(ContainSubstring(peersBase + "gone"))
		Expect(peers(dir, "list")).To(Equal("laptop\n"))
	})

	It("fails when a soft-deleted empty entry cannot be destroyed", func() {
		dir := registry([]string{"gone"}, nil)
		Expect(os.WriteFile(filepath.Join(dir, "delete-error"), []byte("!! 403 permission denied\n"), 0o644)).To(Succeed())
		out, err := removePeer(dir, "gone")
		Expect(err).To(HaveOccurred())
		Expect(out).To(ContainSubstring("could not be destroyed"))
		Expect(out).To(ContainSubstring("permission denied"))
	})

	It("archives an entry that has data but no public key instead of destroying it", func() {
		dir := registry([]string{"broken"}, []string{"broken"})
		Expect(os.Remove(filepath.Join(dir, "live", peersBase, "broken", "public"))).To(Succeed())
		out, err := removePeer(dir, "broken")
		Expect(err).ToNot(HaveOccurred(), out)
		Expect(calls(dir)).To(MatchRegexp(`mv ` + peersBase + `broken secret/test/jumpbox/wireguard/revoked/broken-\d+\n`))
		revoked, err := filepath.Glob(filepath.Join(dir, "live", "secret/test/jumpbox/wireguard/revoked", "broken-*", "psk"))
		Expect(err).ToNot(HaveOccurred())
		Expect(revoked).To(HaveLen(1))
	})

	It("refuses a name that is not in the registry", func() {
		dir := registry([]string{"laptop"}, []string{"laptop"})
		out, err := removePeer(dir, "phone")
		Expect(err).To(HaveOccurred())
		Expect(out).To(ContainSubstring("Peer 'phone' is not registered"))
		Expect(calls(dir)).To(Equal(""))
	})

	It("stops on a vault error instead of reading the peer as missing", func() {
		dir := registry([]string{"laptop"}, []string{"laptop"})
		sealVault(dir, "laptop")
		out, err := removePeer(dir, "laptop")
		Expect(err).To(HaveOccurred())
		Expect(out).To(ContainSubstring("Sealed"))
		Expect(calls(dir)).To(Equal(""))
	})
})
