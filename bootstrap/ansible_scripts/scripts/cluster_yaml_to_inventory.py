#!/usr/bin/env python

"""
Takes cluster.yaml and writes out an Ansible inventory file for the cluster.
"""

import argparse
import jinja2
import os
import sys
import yaml
import re


INVENTORY_TEMPLATE = """[localhost]
127.0.0.1 ansible_connection=local

[{{ cluster_name }}:vars]
ansible_ssh_user={{ cluster_ssh_user }}
{% if cluster_hardware_type %}
hardware_type={{ cluster_hardware_type }}
{% endif %}
{% if cluster_ipmi_username %}
ipmi_username={{ cluster_ipmi_username }}
{% endif %}
{% if cluster_ipmi_password %}
ipmi_password={{ cluster_ipmi_password }}
{% endif %}

[{{ cluster_name }}:children]
{{ cluster_name }}-bootstraps
{{ cluster_name }}-cluster

[{{ cluster_name }}-cluster:children]
{{ cluster_name }}-headnodes
{{ cluster_name }}-worknodes
{{ cluster_name }}-diskless-worknodes

[{{ cluster_name }}-worknodes]
{% for item in worknodes|dictsort %}
{% set node = item[0] + " ansible_ssh_host=" + item[1].ip_address %}
{% if item[1].ipmi_address %}
{% set node = node + " ipmi_address=" + item[1].ipmi_address %}
{% if not cluster_ipmi_username %}
{% set node = node + " ipmi_username=" + item[1].ipmi_username %}
{% endif %}
{% if not cluster_ipmi_password %}
{% set node = node + " ipmi_password=" + item[1].ipmi_password %}
{% endif %}
{% endif %}
{% if not cluster_hardware_type %}
{% set node = node + " hardware_type=" + item[1].hardware_type %}
{% endif %}
{{ node }}
{% endfor %}

[{{ cluster_name }}-diskless-worknodes]
{% for item in dworknodes|dictsort %}
{% set node = item[0] + " ansible_ssh_host=" + item[1].ip_address %}
{% if item[1].ipmi_address %}
{% set node = node + " ipmi_address=" + item[1].ipmi_address %}
{% if not cluster_ipmi_username %}
{% set node = node + " ipmi_username=" + item[1].ipmi_username %}
{% endif %}
{% if not cluster_ipmi_password %}
{% set node = node + " ipmi_password=" + item[1].ipmi_password %}
{% endif %}
{% endif %}
{% if not cluster_hardware_type %}
{% set node = node + " hardware_type=" + item[1].hardware_type %}
{% endif %}
{{ node }}
{% endfor %}

[{{ cluster_name }}-headnodes]
{% for item in headnodes|dictsort %}
{% set node = item[0] + " ansible_ssh_host=" + item[1].ip_address %}
{% if item[1].ipmi_address %}
{% set node = node + " ipmi_address=" + item[1].ipmi_address %}
{% if not cluster_ipmi_username %}
{% set node = node + " ipmi_username=" + item[1].ipmi_username %}
{% endif %}
{% if not cluster_ipmi_password %}
{% set node = node + " ipmi_password=" + item[1].ipmi_password %}
{% endif %}
{% endif %}
{% if not cluster_hardware_type %}
{% set node = node + " hardware_type=" + item[1].hardware_type %}
{% endif %}
{{ node }}
{% endfor %}

[{{ cluster_name }}-bootstraps]
{% for item in bootstraps|dictsort %}
{% set node = item[0] + " ansible_ssh_host=" + item[1].ip_address %}
{% if item[1].ipmi_address %}
{% set node = node + " ipmi_address=" + item[1].ipmi_address %}
{% if not cluster_ipmi_username %}
{% set node = node + " ipmi_username=" + item[1].ipmi_username %}
{% endif %}
{% if not cluster_ipmi_password %}
{% set node = node + " ipmi_password=" + item[1].ipmi_password %}
{% endif %}
{% endif %}
{% if not cluster_hardware_type %}
{% set node = node + " hardware_type=" + item[1].hardware_type %}
{% endif %}
{{ node }}
{% endfor %}

{% for group_space in group_map|dictsort %}
{% set group_space_key = group_space[0] %}
{% for group_set in group_space[1]|dictsort %}
{% set group_set_key = group_set[0] %}
{% set prefix = group_opts_map[group_space_key].prefix %}
[{{ cluster_name }}-{{ prefix }}{{ group_set_key }}]
{% for item in group_set[1]|dictsort %}
{% set node = item[0] + " ansible_ssh_host=" + item[1].ip_address %}
{% if item[1].ipmi_address %}
{% set node = node + " ipmi_address=" + item[1].ipmi_address %}
{% endif %}
{% if not cluster_hardware_type %}
{% set node = node + " hardware_type=" + item[1].hardware_type %}
{% endif %}
{% if not cluster_ipmi_username %}
{% set node = node + " ipmi_username=" + item[1].ipmi_username %}
{% endif %}
{% if not cluster_ipmi_password %}
{% set node = node + " ipmi_password=" + item[1].ipmi_password %}
{% endif %}
{{ node }}
{% endfor %}

{% endfor %}

{% endfor %}

[cluster:children]
headnodes
worknodes

[bootstraps:children]
{{ cluster_name }}-bootstraps

[headnodes:children]
{{ cluster_name }}-headnodes

[worknodes:children]
{{ cluster_name }}-worknodes

[diskless-worknodes:children]
{{ cluster_name }}-diskless-worknodes

{% for group_space in group_map|dictsort %}
{% set group_space_key = group_space[0] %}
{% for group_set in group_space[1]|dictsort %}
{% set group_set_key = group_set[0] %}
{% set prefix = group_opts_map[group_space_key].prefix %}
[{{ prefix }}{{ group_set_key }}:children]
{{ cluster_name }}-{{ prefix }}{{ group_set_key }}

{% endfor %}
{% endfor %}

"""


def parse_grouping_opts(groupstr=None):
    REQUIRED_KEYS = ['prefix', 'grouping_key', 'host_pattern']
    set_delim = ';'
    set_label_delim = ':'
    kvp_delim = ','
    param_delim = '='
    opts = {}

    if groupstr:
        try:
            for oset in groupstr.split(set_delim):
                split_line = oset.split(set_label_delim)
                if len(split_line) != 2 or split_line[1].strip() == '':
                    sys.exit('malformed grouping option string')
                set_label = split_line[0]
                opts[set_label] = {}
                for kvp in split_line[1].split(kvp_delim):
                    k, v = kvp.split(param_delim)
                    opts[set_label][k] = v
        except ValueError as x:
            sys.exit('grouping parsing error: %s' % x.message)

        for k in REQUIRED_KEYS:
            if k not in opts[set_label]:
                sys.exit('%s is missing for grouping \'%s\'' % (k, set_label))

        try:
            pattern = opts[set_label]['host_pattern']
            opts[set_label]['regex'] = re.compile(pattern)
        except re.error as ex:
            sys.exit('%s:<host_pattern>: %s' % (set_label, ex.message))
        # Verify that grouping makes sense with the supplied key
        k = opts[set_label]['grouping_key']
        if k not in opts[set_label]['regex'].groupindex:
            sys.exit("grouping_key \'%s\' must match a named group "
                     "given by host_pattern" % opts[set_label]['grouping_key'])
    return opts


def render_inventory(path, ssh_user, opts={}):
    g_opts = parse_grouping_opts(opts['grouping'])

    f = open(path)
    cluster_yaml = f.read()
    f.close()
    cluster = yaml.safe_load(cluster_yaml)

    # if it's a string and not a dict, something not YAML was loaded
    if type(cluster) != dict:
        sys.exit("ERROR: %s did not parse as YAML. Exiting." % path)

    env = jinja2.Environment(trim_blocks=True, lstrip_blocks=True)
    template = env.from_string(INVENTORY_TEMPLATE)

    hardware_types = set()
    ipmi_usernames = set()
    ipmi_passwords = set()
    bootstraps = {}
    headnodes = {}
    worknodes = {}
    dworknodes = {}
    cluster_hardware_type = None
    cluster_ipmi_username = None
    cluster_ipmi_password = None
    group_map = {}

    for node in cluster['nodes']:
        hardware_types.add(cluster['nodes'][node]['hardware_type'])
        ipmi_usernames.add(cluster['nodes'][node]['ipmi_username'])
        ipmi_passwords.add(cluster['nodes'][node]['ipmi_password'])

        if cluster['nodes'][node]['role'] == 'bootstrap':
            bootstraps[node] = cluster['nodes'][node]
        elif cluster['nodes'][node]['role'] == 'head':
            headnodes[node] = cluster['nodes'][node]
        elif cluster['nodes'][node]['role'] == 'work':
            worknodes[node] = cluster['nodes'][node]
        elif cluster['nodes'][node]['role'] == 'work-diskless':
            dworknodes[node] = cluster['nodes'][node]
        # Do the grouping here
        for group_name, group_params in g_opts.iteritems():
            if group_name not in group_map:
                group_map[group_name] = {}
            grouping_key = group_params['grouping_key']
            m = group_params['regex'].match(node)
            if m and grouping_key in m.groupdict():
                group_item_key = m.groupdict()[grouping_key]
                if group_item_key not in group_map[group_name]:
                    group_map[group_name][group_item_key] = {}
                group_map[group_name][group_item_key][node] = \
                    cluster['nodes'][node]
    # if None is detected as a hardware_type, the person needs to update
    # the YAML to actually have real hardware types
    if None in hardware_types:
        err = "ERROR: null is not a valid hardware type. "
        err += "Please set valid hardware types."
        sys.exit(err)
    # if only one hardware type was detected, we can avoid writing it out
    # for each node separately (Ansible doesn't care, but it reduces
    # visual clutter)
    if len(hardware_types) == 1:
        cluster_hardware_type = hardware_types.pop()
    # same for IPMI username/password
    if len(ipmi_usernames) == 1:
        cluster_ipmi_username = ipmi_usernames.pop()
    if len(ipmi_passwords) == 1:
        cluster_ipmi_password = ipmi_passwords.pop()

    template_vars = {
        'cluster_name': cluster['cluster_name'],
        'cluster_hardware_type': cluster_hardware_type,
        'cluster_ipmi_username': cluster_ipmi_username,
        'cluster_ipmi_password': cluster_ipmi_password,
        'cluster_ssh_user': ssh_user,
        'bootstraps': bootstraps,
        'headnodes': headnodes,
        'worknodes': worknodes,
        'dworknodes': dworknodes,
        'group_map': group_map,
        'group_opts_map': g_opts
    }
    return template.render(template_vars)


def main():
    parser = argparse.ArgumentParser(
        description='Takes cluster.yaml and emits an Ansible inventory.',
        formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument('path', help='path to cluster.yaml')
    parser.add_argument(
        '-G', '--grouping',
        help='''set the grouping options

If appears multiple times, last occurring value takes precedence
The format is as follows:
<label>:grouping_key=<str>,host_pattern=<some_regex>,prefix=<some_prefix>

The grouping_key needs to correspond to a named group specified inside the
regex supplied for host_pattern.

For example if using test data generated by `create_random_cluster_txt.py`
and wanting to group by rack, try the following argument:

--grouping rack:grouping_key='rack_id',
host_pattern='fake-node-r(?P<rack_id>\d+)n\d',prefix='rack-'
             '''
                        )
    parser.add_argument(
        '-s', '--ssh_user',
        help='write this as ansible_ssh_user (default: %(default)s)',
        default='operations')
    args = parser.parse_args()

    if not os.path.exists(args.path) or not os.access(args.path, os.R_OK):
        sys.exit("ERROR: Unable to open %s" % args.path)

    print(render_inventory(args.path, args.ssh_user, args.__dict__))


if __name__ == "__main__":
    main()
