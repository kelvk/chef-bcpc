import hashlib

# See
# https://github.com/openstack/keystone/blob/stable/pike/keystone/identity/id_generators/sha256.py
class NetworkIDGenerator(object):
    def __init__(self):
        pass

    def generate_id(self, mapping):
        h = hashlib.sha256()
        for k in sorted(mapping.keys()):
            h.update(str(mapping[k]).encode('utf-8'))
        return h.hexdigest()


if __name__ == '__main__':
    import sys
    try:
        import simplejson as json
    except ImportError:
        import json

    try:
        mapping_file = sys.argv[1]
    except IndexError:
        sys.exit('Supply a mapping file')

    g = NetworkIDGenerator()
    with open(mapping_file, 'r') as f:
        mapping = json.load(f)
        print(g.generate_id(mapping))
