package cmd

import (
	"context"
	"encoding/binary"
	"fmt"
	"net"
	"strings"
	"time"
)

// assessInstallDomain reports public DNS observation separately from external
// reachability. No port-80 reachability claim is made without an outside probe.
func assessInstallDomain(domain string, lookup func(context.Context, string) ([]net.IP, error)) string {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	addresses, err := lookup(ctx, domain)
	if err != nil || len(addresses) == 0 {
		return fmt.Sprintf("%s is not confirmed in public DNS, so an automatic public certificate cannot be promised. Use local development for testing, or publish the name and allow inbound port 80 before using standalone.", domain)
	}
	return fmt.Sprintf("%s appears in public DNS; external access on port 80 has not been checked, so an automatic public certificate is not yet confirmed.", domain)
}

// Query the public resolver directly instead of net.Resolver.LookupIP, whose
// host lookup order may consult /etc/hosts even with a custom Dial function.
func publicDomainLookup(ctx context.Context, domain string) ([]net.IP, error) {
	var addresses []net.IP
	for _, recordType := range []uint16{1, 28} {
		result, err := publicDNSQuery(ctx, domain, recordType)
		if err != nil {
			return nil, err
		}
		addresses = append(addresses, result...)
	}
	return addresses, nil
}

func publicDNSQuery(ctx context.Context, domain string, recordType uint16) ([]net.IP, error) {
	conn, err := (&net.Dialer{Timeout: 2 * time.Second}).DialContext(ctx, "udp", "1.1.1.1:53")
	if err != nil {
		return nil, err
	}
	defer func() { _ = conn.Close() }()
	deadline := time.Now().Add(2 * time.Second)
	if d, ok := ctx.Deadline(); ok && d.Before(deadline) {
		deadline = d
	}
	if err := conn.SetDeadline(deadline); err != nil {
		return nil, err
	}
	query := make([]byte, 12, 512)
	binary.BigEndian.PutUint16(query[:2], 0x4b71)
	binary.BigEndian.PutUint16(query[2:4], 0x0100)
	binary.BigEndian.PutUint16(query[4:6], 1)
	for _, label := range strings.Split(strings.TrimSuffix(domain, "."), ".") {
		if len(label) == 0 || len(label) > 63 {
			return nil, fmt.Errorf("invalid domain name")
		}
		query = append(query, byte(len(label)))
		query = append(query, label...)
	}
	query = append(query, 0, byte(recordType>>8), byte(recordType), 0, 1)
	if _, err = conn.Write(query); err != nil {
		return nil, err
	}
	response := make([]byte, 4096)
	count, err := conn.Read(response)
	if err != nil {
		return nil, err
	}
	response = response[:count]
	if len(response) < 12 || binary.BigEndian.Uint16(response[:2]) != 0x4b71 || response[2]&0x80 == 0 {
		return nil, fmt.Errorf("invalid public DNS response")
	}
	if response[3]&0x0f != 0 {
		return nil, nil
	} // NXDOMAIN or resolver refusal; no certificate promise
	pos := 12
	for n := 0; n < int(binary.BigEndian.Uint16(response[4:6])); n++ {
		pos, err = skipDNSName(response, pos)
		if err != nil {
			return nil, err
		}
		pos += 4
		if pos > len(response) {
			return nil, fmt.Errorf("invalid public DNS question")
		}
	}
	var addresses []net.IP
	for n := 0; n < int(binary.BigEndian.Uint16(response[6:8])); n++ {
		pos, err = skipDNSName(response, pos)
		if err != nil {
			return nil, err
		}
		if pos+10 > len(response) {
			return nil, fmt.Errorf("invalid public DNS answer")
		}
		kind := binary.BigEndian.Uint16(response[pos:])
		size := int(binary.BigEndian.Uint16(response[pos+8:]))
		pos += 10
		if pos+size > len(response) {
			return nil, fmt.Errorf("invalid public DNS address")
		}
		if kind == recordType && (size == 4 || size == 16) {
			addresses = append(addresses, append(net.IP(nil), response[pos:pos+size]...))
		}
		pos += size
	}
	return addresses, nil
}
func skipDNSName(data []byte, pos int) (int, error) {
	for {
		if pos >= len(data) {
			return 0, fmt.Errorf("invalid public DNS name")
		}
		length := int(data[pos])
		pos++
		if length == 0 {
			return pos, nil
		}
		if length&0xc0 == 0xc0 {
			if pos >= len(data) {
				return 0, fmt.Errorf("invalid public DNS pointer")
			}
			return pos + 1, nil
		}
		if length > 63 || pos+length > len(data) {
			return 0, fmt.Errorf("invalid public DNS label")
		}
		pos += length
	}
}
