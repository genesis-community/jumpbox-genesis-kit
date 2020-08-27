package spec_test

import (
	"path/filepath"
	"runtime"

	. "github.com/genesis-community/testkit/testing"
	. "github.com/onsi/ginkgo"
)

var _ = Describe("Jumpbox Kit", func() {
	BeforeSuite(func() {
		_, filename, _, _ := runtime.Caller(0)
		KitDir, _ = filepath.Abs(filepath.Join(filepath.Dir(filename), "../"))
	})

	Describe("jumpbox", func() {
		Test(Environment{
			Name:        "base",
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
			Name:        "all-features-all-params",
			CloudConfig: "aws",
			CPI:         "aws",
		})

	})
})
