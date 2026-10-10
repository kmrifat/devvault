// vectorcheck independently verifies docs/format/vectors against the vault
// format spec (docs/format/SPEC.md), using only Go's x/crypto. It shares no
// code with the Dart implementation, which is the point: if both agree, the
// spec is complete enough to build another client from. It is also the seed
// of the future Go CLI.
//
//	go run . ../../docs/format/vectors
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"golang.org/x/crypto/argon2"
	"golang.org/x/crypto/blake2b"
	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/hkdf"
	"golang.org/x/text/unicode/norm"
)

var typeCodes = map[string]byte{
	"item": 1, "app": 2, "blob": 3, "tombstone": 4,
	"vk_wrap_password": 5, "vk_wrap_recovery": 6, "organization": 7,
}

var folders = map[string]string{
	"items": "item", "apps": "app", "blobs": "blob", "tombstones": "tombstone",
	"organizations": "organization",
}

const crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

func must[T any](v T, err error) T {
	if err != nil {
		fail("%v", err)
	}
	return v
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "FAIL: "+format+"\n", args...)
	os.Exit(1)
}

func ok(format string, args ...any) { fmt.Printf("ok   "+format+"\n", args...) }

func unhex(s string) []byte { return must(hex.DecodeString(s)) }

// SPEC §5
func openEnvelope(key []byte, vaultID, objectID, objectType string, env []byte) ([]byte, error) {
	if len(env) < 6+24+16 || !bytes.Equal(env[:4], []byte("DVLT")) || env[4] != 1 ||
		env[5] != typeCodes[objectType] {
		return nil, errors.New("bad header")
	}
	aead := must(chacha20poly1305.NewX(key))
	aad := []byte(vaultID + "|" + objectID + "|" + objectType + "|1")
	return aead.Open(nil, env[6:30], env[30:], aad)
}

func sealEnvelope(key []byte, vaultID, objectID, objectType string, nonce, plaintext []byte) []byte {
	aead := must(chacha20poly1305.NewX(key))
	aad := []byte(vaultID + "|" + objectID + "|" + objectType + "|1")
	env := append([]byte("DVLT"), 1, typeCodes[objectType])
	env = append(env, nonce...)
	return aead.Seal(env, nonce, plaintext, aad)
}

// SPEC §4.3
func recoveryKEK(recoveryKey []byte, vaultID string) []byte {
	out := make([]byte, 32)
	must(io.ReadFull(hkdf.New(sha256.New, recoveryKey, []byte(vaultID), []byte("devvault/v1/recovery-kek")), out))
	return out
}

// SPEC §4.4
func vkID(vk []byte) string {
	h := must(blake2b.New256(vk))
	h.Write([]byte("devvault/v1/vk-id"))
	return hex.EncodeToString(h.Sum(nil))
}

// SPEC §8
func parseRecoveryKey(text string) ([]byte, error) {
	var symbols []int
	for _, r := range strings.ToUpper(text) {
		switch r {
		case '-', ' ':
			continue
		case 'I', 'L':
			r = '1'
		case 'O':
			r = '0'
		}
		i := strings.IndexRune(crockford, r)
		if i < 0 {
			return nil, fmt.Errorf("invalid character %q", r)
		}
		symbols = append(symbols, i)
	}
	if len(symbols) != 56 {
		return nil, fmt.Errorf("want 56 symbols, got %d", len(symbols))
	}
	out := make([]byte, 0, 35)
	buf, bits := 0, 0
	for _, s := range symbols {
		buf = buf<<5 | s
		bits += 5
		if bits >= 8 {
			bits -= 8
			out = append(out, byte(buf>>bits))
			buf &= 1<<bits - 1
		}
	}
	key, check := out[:32], out[32:]
	sum := sha256.Sum256(key)
	if check[0] != sum[0] || check[1] != sum[1] || check[2] != sum[2]&0xF0 {
		return nil, errors.New("checksum mismatch")
	}
	return key, nil
}

func encodeRecoveryKey(key []byte) string {
	sum := sha256.Sum256(key)
	data := append(append([]byte{}, key...), sum[0], sum[1], sum[2]&0xF0)
	var sb strings.Builder
	buf, bits := 0, 0
	for _, b := range data {
		buf = buf<<8 | int(b)
		bits += 8
		for bits >= 5 {
			bits -= 5
			sb.WriteByte(crockford[(buf>>bits)&31])
		}
		buf &= 1<<bits - 1
	}
	s := sb.String()
	var groups []string
	for i := 0; i < len(s); i += 4 {
		groups = append(groups, s[i:i+4])
	}
	return strings.Join(groups, "-")
}

func checkVectors(dir string) {
	var v struct {
		Argon2id []struct {
			Password           string `json:"password"`
			PasswordUTF8NFCHex string `json:"password_utf8_nfc_hex"`
			SaltHex            string `json:"salt_hex"`
			OpsLimit           int    `json:"ops_limit"`
			MemLimit           int    `json:"mem_limit"`
			KeyHex             string `json:"key_hex"`
		} `json:"argon2id"`
		RecoveryKEK []struct {
			RecoveryKeyHex  string `json:"recovery_key_hex"`
			RecoveryKeyText string `json:"recovery_key_text"`
			VaultID         string `json:"vault_id"`
			KekHex          string `json:"kek_hex"`
		} `json:"recovery_kek"`
		VkID []struct {
			VkHex string `json:"vk_hex"`
			VkID  string `json:"vk_id"`
		} `json:"vk_id"`
		Envelope []struct {
			Key          string `json:"key"`
			VaultID      string `json:"vault_id"`
			ObjectID     string `json:"object_id"`
			ObjectType   string `json:"object_type"`
			PlaintextHex string `json:"plaintext_hex"`
			EnvelopeHex  string `json:"envelope_hex"`
		} `json:"envelope"`
		HlcSorted  []string `json:"hlc_sorted"`
		AppRecords []struct {
			About       string             `json:"about"`
			Record      map[string]any     `json:"record"`
			Canonical   string             `json:"canonical"`
			Identifiers []appIdentifierVec `json:"identifiers"`
		} `json:"app_records"`
		OrganizationRecords []struct {
			About     string         `json:"about"`
			Record    map[string]any `json:"record"`
			Canonical string         `json:"canonical"`
		} `json:"organization_records"`
	}
	must(0, json.Unmarshal(must(os.ReadFile(filepath.Join(dir, "vectors.json"))), &v))
	// An empty group would silently check nothing.
	if len(v.Argon2id) == 0 || len(v.RecoveryKEK) == 0 || len(v.VkID) == 0 ||
		len(v.Envelope) == 0 || len(v.HlcSorted) < 2 {
		fail("a vector group is empty")
	}

	for _, a := range v.Argon2id {
		pw := norm.NFC.String(a.Password)
		if hex.EncodeToString([]byte(pw)) != a.PasswordUTF8NFCHex {
			fail("argon2id password bytes")
		}
		key := argon2.IDKey([]byte(pw), unhex(a.SaltHex), uint32(a.OpsLimit), uint32(a.MemLimit/1024), 1, 32)
		if hex.EncodeToString(key) != a.KeyHex {
			fail("argon2id key")
		}
	}
	ok("argon2id (%d)", len(v.Argon2id))

	for _, r := range v.RecoveryKEK {
		if hex.EncodeToString(recoveryKEK(unhex(r.RecoveryKeyHex), r.VaultID)) != r.KekHex {
			fail("recovery kek")
		}
		if encodeRecoveryKey(unhex(r.RecoveryKeyHex)) != r.RecoveryKeyText {
			fail("recovery key text encoding")
		}
		if hex.EncodeToString(must(parseRecoveryKey(strings.ToLower(r.RecoveryKeyText)))) != r.RecoveryKeyHex {
			fail("recovery key text parsing")
		}
	}
	ok("recovery key text + HKDF (%d)", len(v.RecoveryKEK))

	for _, k := range v.VkID {
		if vkID(unhex(k.VkHex)) != k.VkID {
			fail("vk_id")
		}
	}
	ok("vk_id (%d)", len(v.VkID))

	for _, e := range v.Envelope {
		env := unhex(e.EnvelopeHex)
		pt := must(openEnvelope(unhex(e.Key), e.VaultID, e.ObjectID, e.ObjectType, env))
		if hex.EncodeToString(pt) != e.PlaintextHex {
			fail("envelope plaintext")
		}
		// Re-seal with the same nonce: must be byte-identical.
		if !bytes.Equal(sealEnvelope(unhex(e.Key), e.VaultID, e.ObjectID, e.ObjectType, env[6:30], pt), env) {
			fail("envelope re-seal")
		}
		// The same bytes in another slot must not open.
		if _, err := openEnvelope(unhex(e.Key), e.VaultID, "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", e.ObjectType, env); err == nil {
			fail("envelope opened in another slot")
		}
	}
	ok("envelopes (%d)", len(v.Envelope))

	if !sort.StringsAreSorted(v.HlcSorted) {
		fail("hlc string order")
	}
	ok("hlc order (%d)", len(v.HlcSorted))

	if len(v.AppRecords) == 0 {
		fail("app_records is empty")
	}
	for _, a := range v.AppRecords {
		app, ids := normalizeApp(a.Record)
		if got := canonicalJSON(app); got != a.Canonical {
			fail("app record %q: canonical\n got  %s\n want %s", a.About, got, a.Canonical)
		}
		if !identifiersEqual(ids, a.Identifiers) {
			fail("app record %q: identifiers %v, want %v", a.About, ids, a.Identifiers)
		}
		// Normalizing is idempotent: the canonical form rewrites to itself.
		var again map[string]any
		must(0, json.Unmarshal([]byte(a.Canonical), &again))
		if back, _ := normalizeApp(again); canonicalJSON(back) != a.Canonical {
			fail("app record %q: canonical form is not stable", a.About)
		}
	}
	ok("app records (%d)", len(v.AppRecords))

	if len(v.OrganizationRecords) == 0 {
		fail("organization_records is empty")
	}
	for _, o := range v.OrganizationRecords {
		if got := canonicalJSON(normalizeOrganization(o.Record)); got != o.Canonical {
			fail("organization record %q: canonical\n got  %s\n want %s", o.About, got, o.Canonical)
		}
		var again map[string]any
		must(0, json.Unmarshal([]byte(o.Canonical), &again))
		if canonicalJSON(normalizeOrganization(again)) != o.Canonical {
			fail("organization record %q: canonical form is not stable", o.About)
		}
	}
	ok("organization records (%d)", len(v.OrganizationRecords))
}

// normalizeOrganization applies SPEC §6.7's writer rules to a decoded
// organization record: name trimmed, notes trimmed and left out when
// empty or null. Everything else, unknown fields too, is kept.
func normalizeOrganization(in map[string]any) map[string]any {
	out := map[string]any{}
	for k, v := range in {
		out[k] = v
	}
	if name, isString := out["name"].(string); isString {
		out["name"] = strings.TrimSpace(name)
	}
	notes, _ := out["notes"].(string)
	if notes = strings.TrimSpace(notes); notes == "" {
		delete(out, "notes")
	} else {
		out["notes"] = notes
	}
	return out
}

func toAny(list []string) []any {
	out := []any{}
	for _, s := range list {
		out = append(out, s)
	}
	return out
}

type appIdentifierVec struct {
	Kind  string `json:"kind"`
	Value string `json:"value"`
}

func identifiersEqual(a, b []appIdentifierVec) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// canonicalJSON is SPEC §6's record encoding: compact UTF-8 JSON, keys
// sorted, nothing escaped that needn't be.
func canonicalJSON(v any) string {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	must(0, enc.Encode(v))
	return strings.TrimSuffix(buf.String(), "\n")
}

// normalizeApp applies SPEC §6.2's writer rules to a decoded app record:
// organization, kind and notes trimmed (left out when empty), identifier
// values trimmed, empty ones and repeats within a kind dropped, bundle_id and
// package_name entries moved to bundle_ids / package_names. It returns the
// record a conforming writer stores and every identifier a reader shows:
// bundle IDs, package names, then the identifiers array in order.
func normalizeApp(in map[string]any) (map[string]any, []appIdentifierVec) {
	out := map[string]any{}
	for k, v := range in {
		out[k] = v
	}
	for _, key := range []string{"organization", "kind", "notes"} {
		s, _ := out[key].(string)
		if s = strings.TrimSpace(s); s == "" {
			delete(out, key)
		} else {
			out[key] = s
		}
	}

	legacy := map[string][]string{}
	for key, kind := range map[string]string{"bundle_ids": "bundle_id", "package_names": "package_name"} {
		list, _ := in[key].([]any)
		for _, v := range list {
			legacy[kind] = append(legacy[kind], v.(string))
		}
	}
	var others []any
	type seenKey struct{ kind, value string }
	seen := map[seenKey]bool{}
	entries, _ := in["identifiers"].([]any)
	for _, e := range entries {
		entry := e.(map[string]any)
		kind := strings.TrimSpace(entry["kind"].(string))
		value := strings.TrimSpace(entry["value"].(string))
		if kind == "" || value == "" {
			continue
		}
		if kind == "bundle_id" || kind == "package_name" {
			legacy[kind] = append(legacy[kind], value)
			continue
		}
		if seen[seenKey{kind, value}] {
			continue
		}
		seen[seenKey{kind, value}] = true
		copied := map[string]any{}
		for k, v := range entry {
			copied[k] = v
		}
		copied["kind"], copied["value"] = kind, value
		others = append(others, copied)
	}

	var ids []appIdentifierVec
	for key, kind := range map[string]string{"bundle_ids": "bundle_id", "package_names": "package_name"} {
		values := []any{}
		done := map[string]bool{}
		for _, v := range legacy[kind] {
			if v = strings.TrimSpace(v); v != "" && !done[v] {
				done[v] = true
				values = append(values, v)
			}
		}
		out[key] = values
	}
	for _, kind := range []string{"bundle_id", "package_name"} {
		key := map[string]string{"bundle_id": "bundle_ids", "package_name": "package_names"}[kind]
		for _, v := range out[key].([]any) {
			ids = append(ids, appIdentifierVec{kind, v.(string)})
		}
	}
	if len(others) == 0 {
		delete(out, "identifiers")
	} else {
		out["identifiers"] = others
		for _, o := range others {
			m := o.(map[string]any)
			ids = append(ids, appIdentifierVec{m["kind"].(string), m["value"].(string)})
		}
	}
	return out, ids
}

func checkMiniVault(dir string) {
	var expected struct {
		Password        string `json:"password"`
		RecoveryKeyText string `json:"recovery_key_text"`
		VaultID         string `json:"vault_id"`
		VkID            string `json:"vk_id"`
		Items           map[string]struct {
			Type        string            `json:"type"`
			Title       string            `json:"title"`
			Fields      map[string]string `json:"fields"`
			Attachments []struct {
				BlobID   string `json:"blob_id"`
				Filename string `json:"filename"`
				Sha256   string `json:"sha256"`
			} `json:"attachments"`
			Notes *string `json:"notes"`
		} `json:"items"`
		Apps       map[string]string `json:"apps"`
		AppRecords map[string]struct {
			Name         string             `json:"name"`
			Organization *string            `json:"organization"`
			Kind         *string            `json:"kind"`
			BundleIDs    []string           `json:"bundle_ids"`
			PackageNames []string           `json:"package_names"`
			Identifiers  []appIdentifierVec `json:"identifiers"`
			Notes        *string            `json:"notes"`
		} `json:"app_records"`
		Organizations       map[string]string `json:"organizations"`
		OrganizationRecords map[string]struct {
			Name  string  `json:"name"`
			Notes *string `json:"notes"`
		} `json:"organization_records"`
		Tombstones []string `json:"tombstones"`
	}
	must(0, json.Unmarshal(must(os.ReadFile(filepath.Join(dir, "mini-vault.json"))), &expected))
	root := filepath.Join(dir, "mini-vault", expected.VaultID)

	var header struct {
		Format        string `json:"format"`
		FormatVersion int    `json:"format_version"`
		VaultID       string `json:"vault_id"`
		Kdf           struct {
			Alg      string `json:"alg"`
			OpsLimit int    `json:"ops_limit"`
			MemLimit int    `json:"mem_limit"`
			Salt     string `json:"salt"`
		} `json:"kdf"`
		WrappedPassword string `json:"wrapped_vk_password"`
		WrappedRecovery string `json:"wrapped_vk_recovery"`
		VkID            string `json:"vk_id"`
	}
	must(0, json.Unmarshal(must(os.ReadFile(filepath.Join(root, "vault.json"))), &header))
	if header.Format != "devvault" || header.FormatVersion != 1 || header.Kdf.Alg != "argon2id13" {
		fail("vault.json header")
	}
	if header.Kdf.OpsLimit < 1 || header.Kdf.OpsLimit > 10 || header.Kdf.MemLimit < 8<<20 || header.Kdf.MemLimit > 1<<30 {
		fail("kdf bounds")
	}

	// Unlock with the password (SPEC §4.2) ...
	salt := must(base64.StdEncoding.DecodeString(header.Kdf.Salt))
	kek := argon2.IDKey([]byte(norm.NFC.String(expected.Password)), salt,
		uint32(header.Kdf.OpsLimit), uint32(header.Kdf.MemLimit/1024), 1, 32)
	vk := must(openEnvelope(kek, header.VaultID, header.VaultID, "vk_wrap_password",
		must(base64.StdEncoding.DecodeString(header.WrappedPassword))))
	// ... and with the recovery key (SPEC §4.3, §8).
	rk := must(parseRecoveryKey(expected.RecoveryKeyText))
	vk2 := must(openEnvelope(recoveryKEK(rk, header.VaultID), header.VaultID, header.VaultID,
		"vk_wrap_recovery", must(base64.StdEncoding.DecodeString(header.WrappedRecovery))))
	if !bytes.Equal(vk, vk2) || vkID(vk) != header.VkID || header.VkID != expected.VkID {
		fail("vault key / vk_id")
	}
	ok("mini-vault unlocks with password and recovery key; vk_id matches")

	// Every object opens with AAD built from its location (SPEC §5).
	records := map[string]map[string]any{}
	for folder, objectType := range folders {
		entries, _ := os.ReadDir(filepath.Join(root, folder))
		for _, e := range entries {
			id := strings.TrimSuffix(e.Name(), ".enc")
			env := must(os.ReadFile(filepath.Join(root, folder, e.Name())))
			pt, err := openEnvelope(vk, header.VaultID, id, objectType, env)
			if err != nil {
				fail("%s/%s does not open", folder, e.Name())
			}
			if objectType == "blob" {
				records["blob:"+id] = map[string]any{"sha256": fmt.Sprintf("%x", sha256.Sum256(pt))}
				continue
			}
			var rec map[string]any
			must(0, json.Unmarshal(pt, &rec))
			if rec["id"] != id {
				fail("%s/%s has id %v", folder, id, rec["id"])
			}
			records[objectType+":"+id] = rec
		}
	}

	optional := func(v any) *string {
		if s, isString := v.(string); isString {
			return &s
		}
		return nil
	}
	same := func(a, b *string) bool { return (a == nil && b == nil) || (a != nil && b != nil && *a == *b) }

	secureNotes := 0
	for id, want := range expected.Items {
		rec, found := records["item:"+id]
		if !found || rec["type"] != want.Type || rec["title"] != want.Title {
			fail("item %s", id)
		}
		if !same(optional(rec["notes"]), want.Notes) {
			fail("item %s notes", id)
		}
		attachments, _ := rec["attachments"].([]any)
		if len(attachments) != len(want.Attachments) {
			fail("item %s has %d attachments, want %d", id, len(attachments), len(want.Attachments))
		}
		// SPEC §6.5: a secure note's body is its notes; it has no attachment.
		if want.Type == "secure_note" {
			if body := optional(rec["notes"]); body == nil || *body == "" || len(attachments) != 0 {
				fail("secure note %s", id)
			}
			secureNotes++
		}
		fields := rec["fields"].(map[string]any)
		for k, v := range want.Fields {
			if fields[k].(map[string]any)["value"] != v {
				fail("item %s field %s", id, k)
			}
		}
		for _, a := range want.Attachments {
			blob, found := records["blob:"+a.BlobID]
			if !found || blob["sha256"] != a.Sha256 {
				fail("attachment %s of item %s", a.Filename, id)
			}
		}
	}
	for id, name := range expected.Apps {
		if records["app:"+id]["name"] != name {
			fail("app %s", id)
		}
	}
	if secureNotes == 0 {
		fail("mini-vault has no secure note")
	}
	// SPEC §6.2: the stored app records are already in canonical form.
	for id, want := range expected.AppRecords {
		rec := records["app:"+id]
		if rec == nil || rec["name"] != want.Name {
			fail("app record %s", id)
		}
		normalized, _ := normalizeApp(rec)
		if canonicalJSON(normalized) != canonicalJSON(rec) {
			fail("app record %s is not in canonical form", id)
		}
		if !same(optional(rec["organization"]), want.Organization) || !same(optional(rec["kind"]), want.Kind) {
			fail("app record %s organization / kind", id)
		}
		if !same(optional(rec["notes"]), want.Notes) {
			fail("app record %s notes", id)
		}
		var ids []appIdentifierVec
		if list, _ := rec["identifiers"].([]any); list != nil {
			for _, e := range list {
				m := e.(map[string]any)
				ids = append(ids, appIdentifierVec{m["kind"].(string), m["value"].(string)})
			}
		}
		if fmt.Sprint(rec["bundle_ids"]) != fmt.Sprint(toAny(want.BundleIDs)) ||
			fmt.Sprint(rec["package_names"]) != fmt.Sprint(toAny(want.PackageNames)) ||
			!identifiersEqual(ids, want.Identifiers) {
			fail("app record %s identifiers", id)
		}
	}
	ok("mini-vault: %d app records in canonical form", len(expected.AppRecords))
	// SPEC §6.7: an organization record holds a trimmed, non-empty name.
	if len(expected.Organizations) == 0 {
		fail("organizations is empty")
	}
	for id, name := range expected.Organizations {
		rec := records["organization:"+id]
		got, isString := rec["name"].(string)
		if rec == nil || !isString || got != name || got != strings.TrimSpace(got) || got == "" {
			fail("organization %s", id)
		}
	}
	// SPEC §6.7: stored organization records are in canonical form, notes
	// trimmed and left out when empty.
	if len(expected.OrganizationRecords) != len(expected.Organizations) {
		fail("organization_records does not list every organization")
	}
	for id, want := range expected.OrganizationRecords {
		rec := records["organization:"+id]
		if rec == nil || rec["name"] != want.Name {
			fail("organization record %s", id)
		}
		if canonicalJSON(normalizeOrganization(rec)) != canonicalJSON(rec) {
			fail("organization record %s is not in canonical form", id)
		}
		if !same(optional(rec["notes"]), want.Notes) {
			fail("organization record %s notes", id)
		}
	}
	for key := range records {
		if id, isOrg := strings.CutPrefix(key, "organization:"); isOrg {
			if _, listed := expected.Organizations[id]; !listed {
				fail("organization %s is not listed", id)
			}
		}
	}
	for _, id := range expected.Tombstones {
		if records["tombstone:"+id] == nil || records["item:"+id] != nil {
			fail("tombstone %s", id)
		}
	}
	ok("mini-vault: %d items (%d secure notes), %d apps, %d organizations, %d tombstones, attachments match sha256",
		len(expected.Items), secureNotes, len(expected.Apps), len(expected.Organizations), len(expected.Tombstones))
}

func main() {
	dir := "../../docs/format/vectors"
	if len(os.Args) > 1 {
		dir = os.Args[1]
	}
	checkVectors(dir)
	checkMiniVault(dir)
	fmt.Println("all vectors verified")
}
