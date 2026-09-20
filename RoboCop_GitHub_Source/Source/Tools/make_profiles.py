# RoboCop Compatibility Profiles | Author: Joe "Gambit" Bradford
import argparse
import json
import struct
from pathlib import Path
import capstone
import pefile

ROOT = Path(__file__).resolve().parents[2]
FUNCTIONS = [('salary', 0x4F7CC50, 0x4F7CE22, 16), ('death', 0x4F7E850, 0x4F7E8F6, 16), ('params', 0x4F636C0, 0x4F63C24, 15), ('complete', 0x4F63EB0, 0x4F64689, 14)]

def profiles(path):
    data = path.read_bytes()
    pe = pefile.PE(data=data, fast_load=True)
    directory = pe.OPTIONAL_HEADER.DATA_DIRECTORY[3]
    offset = pe.get_offset_from_rva(directory.VirtualAddress)
    entries = list(struct.iter_unpack('<III', data[offset:offset + directory.Size]))
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    result = []
    for name, begin, end, patch in FUNCTIONS:
        segments = [(a - begin, b - begin) for a, b, _ in entries if begin <= a < end]
        if not segments or segments[0][0] != 0 or segments[-1][1] != end - begin:
            raise ValueError(f'{name}: function boundaries differ; inspect before generating profiles')
        for left, right in zip(segments, segments[1:]):
            assert left[1] == right[0]
        offset = pe.get_offset_from_rva(begin)
        code = data[offset:offset + end - begin]
        mask = bytearray(b'\xff' * len(code))
        instructions = list(md.disasm(code, begin))
        assert sum(i.size for i in instructions) == len(code)
        assert patch in {i.address + i.size - begin for i in instructions}
        for ins in instructions:
            if any(o.type == capstone.x86.X86_OP_MEM and o.mem.base == capstone.x86.X86_REG_RIP for o in ins.operands):
                at, size = ins.address - begin + ins.disp_offset, ins.disp_size
                assert size == 4 and at >= patch
                mask[at:at + size] = b'\0' * size
            if ins.mnemonic == 'call' and ins.operands[0].type == capstone.x86.X86_OP_IMM:
                at, size = ins.address - begin + ins.imm_offset, ins.imm_size
                assert size == 4 and at >= patch
                mask[at:at + size] = b'\0' * size
        pattern = bytes(a & b for a, b in zip(code, mask))
        result.append(dict(name=name, pattern=pattern.hex(), mask=mask.hex(), segments=segments, patch_length=patch))
    return result

def header(items):
    lines = ['/* RoboCop Compatibility Profiles | Author: Joe "Gambit" Bradford */']
    for item in items:
        for field in ['pattern', 'mask']:
            values = bytes.fromhex(item[field])
            lines.append(f'static const unsigned char {item["name"]}_{field}[] = {{')
            lines.extend('    ' + ','.join(f'0x{x:02x}' for x in values[n:n+24]) + ',' for n in range(0, len(values), 24))
            lines.append('};')
        lines.append(f'static const RcpSegment {item["name"]}_segments[] = {{' + ','.join('{%d,%d}' % tuple(s) for s in item['segments']) + '};')
    lines.append('static const RcpProfile rcp_profiles[] = {')
    for p in items:
        name = p['name']
        lines.append(f'    {{"{name}",{name}_pattern,{name}_mask,sizeof({name}_pattern),{p["patch_length"]},{name}_segments,sizeof({name}_segments)/sizeof(RcpSegment)}},')
    lines.extend(['};', '#define RCP_PROFILE_COUNT (sizeof(rcp_profiles)/sizeof(RcpProfile))'])
    return '\n'.join(lines) + '\n'

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('executable', type=Path)
    parser.add_argument('--compare', type=Path)
    args = parser.parse_args()
    items = profiles(args.executable)
    if args.compare and items != profiles(args.compare):
        raise SystemExit('Function bodies changed after address normalization; inspect the differences.')
    (ROOT / 'Source/Native/profiles.h').write_text(header(items))
    (ROOT / 'Source/Native/profiles.json').write_text(json.dumps(items, indent=2) + '\n')
    print('Generated full-body profiles for:', ', '.join(p['name'] for p in items))
