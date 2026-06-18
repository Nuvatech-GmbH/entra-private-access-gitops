#!/usr/bin/env python3
import zipfile, xml.etree.ElementTree as ET, re, json, sys
from collections import Counter, defaultdict
from pathlib import Path

def read_xlsx(path):
    with zipfile.ZipFile(path) as z:
        shared = []
        root = ET.fromstring(z.read('xl/sharedStrings.xml'))
        ns = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
        for si in root.findall('m:si', ns):
            texts = [t.text or '' for t in si.iter('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t')]
            shared.append(''.join(texts))
        sheet = ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
        rows_raw = []
        for row in sheet.findall('m:sheetData/m:row', ns):
            cells = {}
            for c in row.findall('m:c', ns):
                ref = c.get('r', '')
                col = re.match(r'([A-Z]+)', ref).group(1)
                t = c.get('t')
                v = c.find('m:v', ns)
                val = v.text if v is not None else ''
                if t == 's' and val:
                    val = shared[int(val)]
                cells[col] = val
            rows_raw.append(cells)
    headers = rows_raw[0]
    records = []
    last_app = last_cg = ''
    for r in rows_raw[1:]:
        rec = {headers[k]: (r.get(k, '') or '').strip() for k in headers}
        if rec.get('applicaton_name'):
            last_app = rec['applicaton_name']
        if rec.get('connector_group'):
            last_cg = rec['connector_group']
        rec['applicaton_name'] = last_app
        rec['connector_group'] = last_cg
        if any(rec.get(k) for k in ['fqdn', 'ip_address', 'cidr_range', 'ip_range_start']):
            records.append(rec)
    return records

def host_for(rec):
    tt = rec['target_type']
    if tt == 'fqdn':
        return rec['fqdn']
    if tt == 'ipAddress':
        return rec['ip_address']
    if tt == 'ipRangeCidr':
        return rec['cidr_range']
    if tt == 'ipRange':
        return f"{rec['ip_range_start']}-{rec['ip_range_end']}"
    if tt == 'dnsSuffix':
        return rec['fqdn']
    return ''

def ports_for(rec):
    p = rec.get('port', '').strip()
    pe = rec.get('port_range_end', '').strip()
    if not p and not pe:
        return []
    if p and pe:
        return [f'{p}-{pe}' if p != pe else p]
    return [p]

def protocols_for(rec):
    p = (rec.get('protocol') or 'tcp').strip().lower().replace(' ', '')
    if p in ('both', 'tcp,udp', 'tcp+udp', 'tcp&udp', 'tcpudp'):
        return ['tcp,udp']
    if p == 'udp':
        return ['udp']
    return ['tcp']

def slug_filename(name):
    s = re.sub(r'[^A-Za-z0-9._-]+', '-', name.strip())
    s = re.sub(r'-{2,}', '-', s).strip('-').lower()
    return s[:100] or 'application'

def yaml_quote(s):
    if not s:
        return '""'
    if any(c in s for c in ':,#{}[]&*!|>\'"@`') or s[0] in '-?':
        return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return s

def build_yaml(app_name, connector, destinations, pilot_group):
    desc = f"Private Access Jumphosts – {app_name} ({connector})."
    lines = [
        'apiVersion: gsa.gitops/v1',
        'kind: PrivateAccessApplication',
        'metadata:',
        f'  name: {yaml_quote(app_name)}',
        f'  description: {yaml_quote(desc)}',
        '  owners:',
        '    - florian.ried@extern.edeka.de',
        '    - ertan.simsek@extern.edeka.de',
        '  changeReference: PILOT-JUMPHOSTS-001',
        '  tags:',
        '    workload: jumphosts',
        '    pilot: "true"',
        'spec:',
        '  applicationType: enterprise',
        '  isAccessibleViaZTNAClient: true',
        f'  connectorGroup: {yaml_quote(connector)}',
        '  destinations:',
    ]
    for d in destinations:
        lines.append(f'    - host: {yaml_quote(d["host"])}')
        lines.append(f'      type: {d["type"]}')
        ports_yaml = ', '.join(f'"{p}"' for p in d['ports'])
        lines.append(f'      ports: [{ports_yaml}]')
        lines.append(f'      protocol: {d["protocol"]}')
    lines += [
        '  assignments:',
        '    - principalType: Group',
        f'      principalName: {yaml_quote(pilot_group)}',
    ]
    return '\n'.join(lines) + '\n'

def main():
    path = Path(__file__).resolve().parents[2] / 'docs/import/Jumphosts_Import.xlsx'
    out_dir = Path(__file__).resolve().parents[2] / 'config/applications'
    pilot = 'EIT_Intune_EIT_cfg Private Access PILOT'
    records = read_xlsx(path)

    grouped = defaultdict(list)
    for rec in records:
        grouped[(rec['applicaton_name'], rec['connector_group'])].append(rec)

    print('apps', len(grouped))
    manifest = []
    warnings = []

    for (app_name, connector), rows in sorted(grouped.items()):
        dest_map = {}
        for rec in rows:
            host = host_for(rec)
            ports = ports_for(rec)
            if not host or not ports:
                warnings.append(f'skip incomplete: {app_name} {rec}')
                continue
            tt = rec['target_type']
            for proto in protocols_for(rec):
                key = (host, tt, proto, tuple(ports))
                dest_map[key] = {'host': host, 'type': tt, 'ports': ports, 'protocol': proto}

        destinations = sorted(dest_map.values(), key=lambda d: (d['type'], d['host'], d['protocol']))
        seg_count = len(destinations)
        if seg_count > 500:
            warnings.append(f'WARN >500 segments ({seg_count}): {app_name} | {connector}')
        if seg_count == 0:
            warnings.append(f'skip empty: {app_name} | {connector}')
            continue

        fname = f'{app_name}.yaml'
        content = build_yaml(app_name, connector, destinations, pilot)
        out_path = out_dir / fname
        out_path.write_text(content, encoding='utf-8')
        manifest.append({
            'file': str(out_path.relative_to(out_dir.parent.parent)),
            'application': app_name,
            'connector_group': connector,
            'segments': seg_count,
            'source_rows': len(rows),
        })
        print(f'wrote {fname}: rows={len(rows)} segments={seg_count}')

    summary_path = out_dir.parent.parent / 'import/output/jumphosts-manifest.json'
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    if warnings:
        print('\nWARNINGS:')
        for w in warnings[:20]:
            print(' ', w)
        if len(warnings) > 20:
            print(f'  ... and {len(warnings)-20} more')

if __name__ == '__main__':
    main()
