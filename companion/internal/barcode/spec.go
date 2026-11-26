// Package barcode implements the NAVTOK v1 barcode (see docs/barcode.md). The encoder mirrors
// addon/NavtokDiscord/Barcode.lua bit for bit; fixture_test.go keeps the two from drifting apart.
package barcode

const (
	Version    = 1
	Rows       = 13
	Cols       = 77
	Quiet      = 2  // white modules around the code
	MaxPayload = 96 // bytes
	ModulePx   = 8  // default module size in physical pixels
)

var magic = [2]byte{'N', 'V'}

// CRC16 is CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection, no final xor.
func CRC16(data []byte) uint16 {
	crc := uint16(0xFFFF)
	for _, b := range data {
		crc ^= uint16(b) << 8
		for i := 0; i < 8; i++ {
			if crc&0x8000 != 0 {
				crc = crc<<1 ^ 0x1021
			} else {
				crc <<= 1
			}
		}
	}
	return crc
}
