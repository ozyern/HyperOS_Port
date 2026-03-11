#!/usr/bin/env python3
"""
payload_dumper.py — Pure-Python payload.bin extractor
Part of HyperOS3-Port-lemonadep  |  Maintainer: Ozyern

Supports: REPLACE, REPLACE_BZ, REPLACE_XZ, ZERO operations
No external protobuf library required — hand-rolled wire-format parser
"""

import sys
import os
import struct
import hashlib
import bz2
import lzma
import argparse
from pathlib import Path


# ─── Minimal protobuf wire-format parser ─────────────────────────────────────
def read_varint(data, pos):
    result = 0
    shift = 0
    while True:
        b = data[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            break
        shift += 7
    return result, pos


def parse_proto(data):
    """Parse a flat protobuf message into {field_number: [values]}"""
    fields = {}
    pos = 0
    while pos < len(data):
        tag, pos = read_varint(data, pos)
        field_num = tag >> 3
        wire_type = tag & 0x7
        if wire_type == 0:  # varint
            val, pos = read_varint(data, pos)
        elif wire_type == 1:  # 64-bit
            val = struct.unpack_from('<Q', data, pos)[0]
            pos += 8
        elif wire_type == 2:  # length-delimited
            length, pos = read_varint(data, pos)
            val = data[pos:pos + length]
            pos += length
        elif wire_type == 5:  # 32-bit
            val = struct.unpack_from('<I', data, pos)[0]
            pos += 4
        else:
            break
        fields.setdefault(field_num, []).append(val)
    return fields


# ─── Payload structure constants ─────────────────────────────────────────────
MAGIC = b'CrAU'
BLOCK_SIZE = 4096

# Operation types
OP_REPLACE    = 0
OP_REPLACE_BZ = 2
OP_ZERO       = 6
OP_REPLACE_XZ = 8
OP_SOURCE_COPY = 3  # A/B only
OP_BSDIFF     = 4


def parse_extent(data):
    fields = parse_proto(data)
    start_block = fields.get(1, [0])[0]
    num_blocks  = fields.get(2, [0])[0]
    return start_block, num_blocks


def parse_operation(data):
    fields = parse_proto(data)
    op_type       = fields.get(1, [OP_REPLACE])[0]
    dst_extents   = [parse_extent(e) for e in fields.get(5, [])]
    data_offset   = fields.get(7, [None])[0]
    data_length   = fields.get(8, [0])[0]
    return op_type, dst_extents, data_offset, data_length


def parse_partition_update(data):
    fields = parse_proto(data)
    name         = fields.get(1, [b''])[0].decode('utf-8', errors='replace')
    operations   = [parse_operation(op) for op in fields.get(8, [])]
    new_size     = fields.get(5, [{}])[0]
    if isinstance(new_size, bytes):
        sz_fields = parse_proto(new_size)
        new_size  = sz_fields.get(1, [0])[0]
    else:
        new_size = 0
    return name, operations, new_size


def extract_payload(payload_path, out_dir, partitions=None):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    with open(payload_path, 'rb') as f:
        magic = f.read(4)
        if magic != MAGIC:
            raise ValueError(f"Not a payload.bin file (magic={magic!r})")

        version      = struct.unpack('>Q', f.read(8))[0]
        manifest_len = struct.unpack('>Q', f.read(8))[0]
        metadata_sig = struct.unpack('>I', f.read(4))[0] if version >= 2 else 0

        manifest_data = f.read(manifest_len)
        if version >= 2:
            f.read(metadata_sig)  # skip signature

        data_offset = f.tell()
        payload_data = f.read()

    # Parse manifest (DeltaArchiveManifest proto)
    manifest_fields = parse_proto(manifest_data)
    block_size = manifest_fields.get(3, [BLOCK_SIZE])[0]
    partition_updates_raw = manifest_fields.get(13, [])  # repeated PartitionUpdate

    print(f"[payload_dumper] format v{version}, {len(partition_updates_raw)} partitions, block_size={block_size}")

    def decompress_op(op_type, raw):
        if op_type == OP_REPLACE:
            return raw
        elif op_type == OP_REPLACE_BZ:
            try:
                return bz2.decompress(raw)
            except Exception as e:
                print(f"    BZ2 warning: {e} — using raw")
                return raw
        elif op_type == OP_REPLACE_XZ:
            # Try multiple approaches for XZ — some payloads have truncated EOS markers
            for fmt in [lzma.FORMAT_XZ, lzma.FORMAT_AUTO, None]:
                try:
                    if fmt is None:
                        return lzma.decompress(raw)
                    dec = lzma.LZMADecompressor(format=fmt)
                    return dec.decompress(raw)
                except lzma.LZMAError:
                    continue
            print(f"    XZ decompress failed — skipping block")
            return b''
        elif op_type == OP_ZERO:
            return None
        return None  # unknown / skip

    def extract_partition(name, operations, new_size, block_size, payload_data, out_dir):
        out_path = out_dir / f"{name}.img"
        print(f"  Extracting: {name} → {out_path}")

        if new_size > 0:
            out_size = new_size
        else:
            blocks = [(s + n) for _, dst_exts, _, _ in operations for s, n in dst_exts]
            out_size = max(blocks) * block_size if blocks else 0

        with open(out_path, 'wb') as out_f:
            if out_size:
                out_f.seek(out_size - 1)
                out_f.write(b'\x00')
                out_f.seek(0)

            for op_type, dst_extents, data_off, data_len in operations:
                raw = payload_data[data_off:data_off + data_len] \
                    if (data_off is not None and data_len > 0) else b''

                if op_type == OP_SOURCE_COPY:
                    continue  # A/B delta — needs source partition, skip
                if op_type not in (OP_REPLACE, OP_REPLACE_BZ, OP_REPLACE_XZ, OP_ZERO):
                    continue  # BSDIFF etc — skip unsupported

                blob = decompress_op(op_type, raw)
                blob_pos = 0

                for start_block, num_blocks in dst_extents:
                    offset = start_block * block_size
                    length = num_blocks * block_size
                    out_f.seek(offset)
                    if blob is None:
                        out_f.write(b'\x00' * length)
                    else:
                        chunk = blob[blob_pos:blob_pos + length]
                        out_f.write(chunk.ljust(length, b'\x00')[:length])
                        blob_pos += length

        size_mb = out_path.stat().st_size / 1024 / 1024
        print(f"  ✓ {name}.img ({size_mb:.1f} MB)")

    failed = []
    for pu_data in partition_updates_raw:
        if not isinstance(pu_data, bytes):
            continue
        name, operations, new_size = parse_partition_update(pu_data)
        if not name:
            continue
        if partitions and name not in partitions:
            continue
        try:
            extract_partition(name, operations, new_size, block_size, payload_data, out_dir)
        except Exception as e:
            print(f"  [WARN] {name}: {e} — skipping, continuing with others")
            failed.append(name)

    if failed:
        print(f"\n[WARN] Partitions with errors: {', '.join(failed)}")
    return failed


# ─── CLI ─────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description='Extract partitions from a payload.bin OTA file')
    parser.add_argument('payload', help='Path to payload.bin')
    parser.add_argument('--out', default='.', help='Output directory (default: .)')
    parser.add_argument('--partitions', nargs='+',
                        help='Only extract these partitions (default: all)')
    parser.add_argument('--list', action='store_true',
                        help='List partitions without extracting')
    args = parser.parse_args()

    if not os.path.isfile(args.payload):
        print(f"Error: {args.payload} not found", file=sys.stderr)
        sys.exit(1)

    if args.list:
        with open(args.payload, 'rb') as f:
            magic = f.read(4)
            if magic != MAGIC:
                print("Not a payload.bin", file=sys.stderr); sys.exit(1)
            version      = struct.unpack('>Q', f.read(8))[0]
            manifest_len = struct.unpack('>Q', f.read(8))[0]
            metadata_sig = struct.unpack('>I', f.read(4))[0] if version >= 2 else 0
            manifest_data = f.read(manifest_len)
        mf = parse_proto(manifest_data)
        for pu in mf.get(13, []):
            if isinstance(pu, bytes):
                fields = parse_proto(pu)
                name = fields.get(1, [b'?'])[0]
                if isinstance(name, bytes):
                    print(f"  {name.decode()}")
        return

    try:
        extract_payload(args.payload, args.out, args.partitions)
        print("\nExtraction complete.")
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
