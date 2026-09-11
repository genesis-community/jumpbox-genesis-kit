package spec_test

import (
	"os/exec"
	"path/filepath"
	"strings"

	. "github.com/genesis-community/testkit/v2/testing"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// sshCommand runs the Perl helper that the ssh and who addons share, and
// returns the argument vector they would hand to exec. The prefix is the word
// the addon always puts in front of the remote command, which is empty for the
// ssh addon and "who" for the who addon.
func sshCommand(prefix string, args ...string) []string {
	helper := filepath.Join(KitDir, "spec", "support", "ssh-command.pl")
	argv := append([]string{helper, "user@10.0.0.1", prefix}, args...)

	out, err := exec.Command("perl", argv...).CombinedOutput()
	Expect(err).ToNot(HaveOccurred(), string(out))

	return strings.Split(strings.TrimRight(string(out), "\n"), "\n")
}

var _ = Describe("the ssh and who addons", func() {

	Context("given no arguments", func() {
		It("opens an interactive session and sends no command", func() {
			Expect(sshCommand("")).To(Equal([]string{"ssh", "user@10.0.0.1"}))
		})
	})

	Context("given arguments after a separator", func() {
		It("runs them on the jumpbox as the remote command", func() {
			Expect(sshCommand("", "--", "hostname")).To(Equal([]string{
				"ssh", "user@10.0.0.1", "--", "hostname",
			}))
		})

		It("quotes each word so the remote shell sees it whole", func() {
			Expect(sshCommand("", "--", "echo", "a  b", "it's")).To(Equal([]string{
				"ssh", "user@10.0.0.1", "--", `echo 'a  b' 'it'\''s'`,
			}))
		})

		It("keeps a command that starts with a dash away from ssh", func() {
			Expect(sshCommand("", "--", "-x")).To(Equal([]string{
				"ssh", "user@10.0.0.1", "--", "-x",
			}))
		})

		It("treats a repeated separator as a single one", func() {
			Expect(sshCommand("", "--", "--", "hostname")).To(Equal([]string{
				"ssh", "user@10.0.0.1", "--", "hostname",
			}))
		})
	})

	Context("given arguments before a separator", func() {
		It("passes them to ssh itself", func() {
			Expect(sshCommand("", "-L", "8080:localhost:80", "--", "uptime", "-p")).To(Equal([]string{
				"ssh", "-L", "8080:localhost:80", "user@10.0.0.1", "--", "uptime -p",
			}))
		})

		It("passes them all to ssh when there is no separator", func() {
			Expect(sshCommand("", "-v")).To(Equal([]string{
				"ssh", "-v", "user@10.0.0.1",
			}))
		})
	})

	Context("the who addon", func() {
		It("always runs who on the jumpbox", func() {
			Expect(sshCommand("who")).To(Equal([]string{
				"ssh", "user@10.0.0.1", "--", "who",
			}))
		})

		It("hands arguments after a separator to who", func() {
			Expect(sshCommand("who", "--", "-a")).To(Equal([]string{
				"ssh", "user@10.0.0.1", "--", "who -a",
			}))
		})
	})
})
