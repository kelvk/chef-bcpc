#!/usr/bin/env python

"""
This script will randomly generate cluster information in the requested format
for testing purposes (so that scripts that work with it can be validated
without needing to be tested on actual cluster.txt or cluster.yaml files
that may contain privileged information).

cluster.txt layout:

column 1: node name
column 2: MAC address of first network interface
column 3: IP address of OS management network
column 4: IPMI/LOM IP address
column 5: domain
column 6: role (bootstrap/head/work)

cluster.yaml schema:

cluster_name: MURF
nodes:
  node1:
    domain: bcpc.example.com
    hardware_type: Virtual
    ip_address: 10.0.100.3
    ipmi_address: 10.10.100.3
    ipmi_username: value
    ipmi_password: value
    mac_address: 00:11:22:33:44:55
    role: bootstrap
    cobbler_profile: bcpc_host
"""

import argparse
import hashlib
import random
import yaml


def generate_random_string():
    """
    Stringify a random number and return some part of the SHA-1 hash to get
    reasonably random string data.
    """
    source = hashlib.sha1(str(random.random())).hexdigest()
    min_bound = random.randint(0, len(source)-2)
    max_bound = random.randint(min_bound+1, len(source)-1)
    return source[min_bound:max_bound]


def generate_cluster_information(
        cluster_name, node_domain, node_prefix, count, rack_step,
        start_at_rack=None):
    """
    Emits cluster information in a dictionary format that can be processed
    into cluster YAML or cluster.txt.
    """
    possible_roles = [
        'bootstrap', 'head', 'work', 'reserved']

    cluster_info = {'cluster_name': cluster_name, 'nodes': {}}

    if start_at_rack is None:
        rack_number = random.randint(1, 12)
    else:
        rack_number = int(start_at_rack)

    node_number = 1

    head_node_count = 0

    for n in range(count):
        node_name = "%s-r%02dn%02d" % (node_prefix, rack_number, node_number)
        mac_address = ":".join(
            ["%02x" % random.randint(0, 255) for i in range(0, 6)])
        ip_address = ".".join(
            [str(random.randint(1, 255)) for i in range(0, 4)])
        # don't always add an IPMI address, virtual nodes don't have them
        if random.randint(0, 1):
            ipmi_address = ".".join(
                [str(random.randint(1, 255)) for i in range(0, 4)])
            ipmi_username = generate_random_string()
            ipmi_password = generate_random_string()
        else:
            ipmi_address = None
            ipmi_username = None
            ipmi_password = None
        role = random.choice(possible_roles)
        hardware_type = 'Fake-%s' % generate_random_string()

        # hack to avoid multiple bootstrap nodes or too many head nodes
        if role == 'bootstrap':
            possible_roles.remove('bootstrap')
        if role == 'head':
            head_node_count += 1
        if head_node_count >= 5:
            if 'head' in possible_roles:
                possible_roles.remove('head')

        cluster_info['nodes'][node_name] = {
            'domain': node_domain,
            'hardware_type': hardware_type,
            'ip_address': ip_address,
            'ipmi_address': ipmi_address,
            'ipmi_username': ipmi_username,
            'ipmi_password': ipmi_password,
            'mac_address': mac_address,
            'role': role,
            'cobbler_profile': generate_random_string()
        }

        node_number += 1
        if node_number > rack_step:
            node_number = 1
            rack_number += 1

    return cluster_info


def render_cluster_info_as_yaml(cluster_info):
    return yaml.dump(cluster_info, default_flow_style=False)

"""
column 1: node name
column 2: MAC address of first network interface
column 3: IP address of OS management network
column 4: IPMI/LOM IP address
column 5: domain
column 6: role (bootstrap/head/work)
"""

def render_cluster_info_as_text(cluster_info):
    rows = []
    column_width = [0, 0, 0, 0, 0, 0]
    rendered_text = ''
    for node in cluster_info['nodes']:
        if cluster_info['nodes'][node]['ipmi_address'] is None:
            ipmi_address = '-'
        else:
            ipmi_address = cluster_info['nodes'][node]['ipmi_address']

        row = [
            node,
            cluster_info['nodes'][node]['mac_address'],
            cluster_info['nodes'][node]['ip_address'],
            ipmi_address,
            cluster_info['nodes'][node]['domain'],
            cluster_info['nodes'][node]['role']]

        for idx, data in enumerate(row):
            if len(data) > column_width[idx]:
                column_width[idx] = len(data)

        rows.append(row)

    rows = sorted(rows)
    rows.append(['end'])

    for row in rows:
        for idx, column in enumerate(row):
            rendered_text += str(column).ljust(column_width[idx]+1)
        rendered_text += "\n"

    return rendered_text


def main():
    parser = argparse.ArgumentParser(
        description='Generate random cluster information')
    parser.add_argument(
        'format', choices=['text', 'yaml'],
        help='Format to output in (text or YAML)')
    parser.add_argument(
        '-n', '--number-of-nodes', type=int,
        default=random.randint(20, 100))
    parser.add_argument(
        '-r', '--rack-step', type=int, default=16)
    parser.add_argument(
        '-s', '--start-at-rack', default=None)
    parser.add_argument(
        '-d', '--domain', default='completelyfake.example')
    parser.add_argument(
        '-p', '--prefix', default='fake-node')
    parser.add_argument(
        '-c', '--cluster-name', default='FAKE')
    args = parser.parse_args()

    cluster_info = generate_cluster_information(
        cluster_name=args.cluster_name,
        node_domain=args.domain,
        node_prefix=args.prefix,
        count=args.number_of_nodes,
        rack_step=args.rack_step,
        start_at_rack=args.start_at_rack)

    if args.format == 'yaml':
        print(render_cluster_info_as_yaml(cluster_info))
    elif args.format == 'text':
        print(render_cluster_info_as_text(cluster_info))
    else:
        raise RuntimeError('not a valid format')


if __name__ == '__main__':
    main()
