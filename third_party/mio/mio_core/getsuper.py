#!/usr/bin/env python3
import os
import sys
import struct
import urllib.request
import zipfile


class RemoteZipFile:
    def __init__(self, url):
        self.url = url
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req) as resp:
            self.size = int(resp.headers.get("Content-Length", 0))
        self.pos = 0

    def read(self, size=-1):
        if size == -1:
            size = self.size - self.pos
        if size == 0:
            return b""
        end = min(self.pos + size - 1, self.size - 1)
        req = urllib.request.Request(self.url)
        req.add_header("Range", f"bytes={self.pos}-{end}")
        with urllib.request.urlopen(req) as resp:
            data = resp.read()
        self.pos += len(data)
        return data

    def seek(self, offset, whence=0):
        if whence == 0:
            self.pos = offset
        elif whence == 1:
            self.pos += offset
        elif whence == 2:
            self.pos = self.size + offset
        return self.pos

    def tell(self):
        return self.pos

    def seekable(self):
        return True


class ProtoReader:
    def __init__(self, data):
        self.data = data
        self.offset = 0
        self.length = len(data)

    def eof(self):
        return self.offset >= self.length

    def read_varint(self):
        result = 0
        shift = 0
        while self.offset < self.length:
            b = self.data[self.offset]
            self.offset += 1
            result |= (b & 0x7F) << shift
            if not (b & 0x80):
                break
            shift += 7
        return result

    def read_tag(self):
        if self.eof():
            return None, None
        key = self.read_varint()
        field_num = key >> 3
        wire_type = key & 7
        return field_num, wire_type

    def skip_wire_type(self, wire_type):
        if wire_type == 0:
            self.read_varint()
        elif wire_type == 1:
            self.offset += 8
        elif wire_type == 2:
            length = self.read_varint()
            self.offset += length
        elif wire_type == 5:
            self.offset += 4
        else:
            raise ValueError(f"Unsupported wire type: {wire_type}")

    def read_bytes(self):
        length = self.read_varint()
        data = self.data[self.offset : self.offset + length]
        self.offset += length
        return data


def extract_super_info(manifest_bytes):
    reader = ProtoReader(manifest_bytes)
    dpm_bytes = None

    while not reader.eof():
        field_num, wire_type = reader.read_tag()
        if field_num == 15 and wire_type == 2:
            dpm_bytes = reader.read_bytes()
            break
        elif field_num is not None:
            reader.skip_wire_type(wire_type)

    if not dpm_bytes:
        return None

    dpm_reader = ProtoReader(dpm_bytes)
    group_bytes = None
    while not dpm_reader.eof():
        field_num, wire_type = dpm_reader.read_tag()
        if field_num == 1 and wire_type == 2:
            group_bytes = dpm_reader.read_bytes()
            break
        elif field_num is not None:
            dpm_reader.skip_wire_type(wire_type)

    if not group_bytes:
        return None

    group_reader = ProtoReader(group_bytes)
    name = ""
    size = 0
    partitions = []

    while not group_reader.eof():
        field_num, wire_type = group_reader.read_tag()
        if field_num == 1 and wire_type == 2:
            name = group_reader.read_bytes().decode("utf-8")
        elif field_num == 2 and wire_type == 0:
            size = group_reader.read_varint()
        elif field_num == 3 and wire_type == 2:
            partitions.append(group_reader.read_bytes().decode("utf-8"))
        elif field_num is not None:
            group_reader.skip_wire_type(wire_type)

    return {"name": name, "size": size, "partition_names": partitions}


def parse_payload_file(f):
    magic = f.read(4)
    if magic != b"CrAU":
        raise ValueError("Invalid payload.bin format")
    version = struct.unpack(">Q", f.read(8))[0]
    ms = struct.unpack(">Q", f.read(8))[0]
    if version == 2:
        f.read(4)
    raw = f.read(ms)
    return raw


def _process_url(url):
    remote_file = RemoteZipFile(url)
    with zipfile.ZipFile(remote_file) as zf:
        if "payload.bin" not in zf.namelist():
            raise ValueError("payload.bin not found in remote zip")
        with zf.open("payload.bin") as f:
            return parse_payload_file(f)


def _process_local(path):
    if not os.path.exists(path):
        raise FileNotFoundError(f"File not found: {path}")

    if path.endswith(".zip"):
        with zipfile.ZipFile(path) as zf:
            if "payload.bin" not in zf.namelist():
                raise ValueError("payload.bin not found in zip")
            with zf.open("payload.bin") as f:
                return parse_payload_file(f)
    else:
        with open(path, "rb") as f:
            return parse_payload_file(f)


def print_bash_vars(raw_manifest):
    info = extract_super_info(raw_manifest)

    if info:
        chunk_size = 128 * 1024 * 1024
        physical_size = round(info["size"] / chunk_size) * chunk_size
        partitions_list = " ".join(info["partition_names"])

        print(f'super_group="{info["name"]}"')
        print(f'super_size="{physical_size}"')
        print(f'super_list="{partitions_list}"')
    else:
        sys.stderr.write("Error: Dynamic Partition Metadata Not Found\n")
        sys.exit(1)


def main():
    if len(sys.argv) < 2:
        sys.stderr.write(
            f"Usage: python3 {os.path.basename(sys.argv[0])} <payload.bin/ota.zip/URL>\n"
        )
        sys.exit(1)

    target = sys.argv[1]

    try:
        if target.startswith(("http://", "https://")):
            raw_manifest = _process_url(target)
        else:
            raw_manifest = _process_local(target)

        print_bash_vars(raw_manifest)
    except Exception as e:
        sys.stderr.write(f"Error: {e}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
