package spec_test

import (
	"path/filepath"
	"runtime"

	. "github.com/genesis-community/testkit/v2/testing"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = BeforeSuite(func() {
	_, filename, _, _ := runtime.Caller(0)
	KitDir, _ = filepath.Abs(filepath.Join(filepath.Dir(filename), "../"))
})

var _ = Describe("Jumpbox Kit", func() {

	Describe("jumpbox", func() {
		Test(Environment{
			Name:        "base",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "null-params",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "bastion",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "openvpn",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "openvpn-no-search-domains",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "wireguard",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "wireguard-all-params",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "openvpn-wireguard",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "wireguard-jammy-stemcell",
			CloudConfig: "aws",
			CPI:         "aws",
			OutputMatchers: OutputMatchers{
				GenesisAddSecrets: ContainSubstring("needs the ubuntu-noble stemcell"),
				GenesisCheck:      ContainSubstring("needs the ubuntu-noble stemcell"),
				GenesisManifest:   ContainSubstring("needs the ubuntu-noble stemcell"),
			},
		})
		Test(Environment{
			Name:        "all-features-all-params",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "stackit",
			CloudConfig: "stackit",
			CPI:         "stackit",
		})

	})

	Describe("resolute", func() {
		Test(Environment{
			Name:        "resolute",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "resolute-wireguard",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "resolute-openvpn",
			CloudConfig: "aws",
			CPI:         "aws",
		})
		Test(Environment{
			Name:        "resolute-wrong-stemcell-os",
			CloudConfig: "aws",
			CPI:         "aws",
			OutputMatchers: OutputMatchers{
				GenesisAddSecrets: ContainSubstring("stemcell os to"),
				GenesisCheck:      ContainSubstring("stemcell os to"),
				GenesisManifest:   ContainSubstring("stemcell os to"),
			},
		})
		Test(Environment{
			Name:        "resolute-stemcell-without-feature",
			CloudConfig: "aws",
			CPI:         "aws",
			OutputMatchers: OutputMatchers{
				GenesisAddSecrets: ContainSubstring("Enable the feature and remove that parameter"),
				GenesisCheck:      ContainSubstring("Enable the feature and remove that parameter"),
				GenesisManifest:   ContainSubstring("Enable the feature and remove that parameter"),
			},
		})
	})
})
