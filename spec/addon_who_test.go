package spec_test

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	. "github.com/genesis-community/testkit/v2/testing"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// whoRun builds the remote command that the who addon sends to the jumpbox and
// runs it under a shell whose PATH holds only sh and the stubs we name. A stub
// prints its own name and exits 0, and a name ending in "=" prints that text
// instead. When utmp is true the file the command tests for exists.
func whoRun(utmp bool, stubs map[string]string) (stdout, stderr string, err error) {
	helper := filepath.Join(KitDir, "spec", "support", "who-script.pl")
	script, perr := exec.Command("perl", helper, "who").Output()
	Expect(perr).ToNot(HaveOccurred())

	bin := GinkgoT().TempDir()
	Expect(os.Symlink("/bin/sh", filepath.Join(bin, "sh"))).To(Succeed())
	for name, output := range stubs {
		body := "#!/bin/sh\nprintf '%s' '" + output + "'\n"
		Expect(os.WriteFile(filepath.Join(bin, name), []byte(body), 0o755)).To(Succeed())
	}

	utmpPath := filepath.Join(GinkgoT().TempDir(), "utmp")
	if utmp {
		Expect(os.WriteFile(utmpPath, nil, 0o644)).To(Succeed())
	}
	command := strings.ReplaceAll(string(script), "/run/utmp", utmpPath)

	cmd := exec.Command("/bin/sh", "-c", command)
	cmd.Env = []string{"PATH=" + bin}
	var out, errOut bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errOut
	err = cmd.Run()
	return out.String(), errOut.String(), err
}

var _ = Describe("the who addon fallback", func() {
	It("runs who where utmp exists", func() {
		out, _, err := whoRun(true, map[string]string{"who": "from-who", "w": "from-w"})
		Expect(err).ToNot(HaveOccurred())
		Expect(out).To(Equal("from-who"))
	})

	It("asks w where utmp is missing", func() {
		out, _, err := whoRun(false, map[string]string{"w": "alice pts/0", "loginctl": "from-logind"})
		Expect(err).ToNot(HaveOccurred())
		Expect(out).To(Equal("alice pts/0\n"))
	})

	It("asks logind when w shows nothing", func() {
		out, _, err := whoRun(false, map[string]string{"w": "", "loginctl": "from-logind"})
		Expect(err).ToNot(HaveOccurred())
		Expect(out).To(Equal("from-logind"))
	})

	It("says so and fails when neither w nor loginctl is installed", func() {
		out, errOut, err := whoRun(false, nil)
		Expect(err).To(HaveOccurred())
		Expect(out).To(BeEmpty())
		Expect(errOut).To(ContainSubstring("neither w nor loginctl is installed"))
	})
})
