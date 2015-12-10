#!/usr/bin/env python

"""
"""

import re
import string
import sys
import subprocess
import yaml
import MySQLdb


class OSQuota(object):
  def __init__(self, config):
    self.db = MySQLdb.connect(read_default_file='/etc/mysql/debian.cnf')
    self.config = config

  """
  Retrieve project/tenant UUID
  """
  def _get_tenant_id(self, project):
    uuid_re = re.compile('[0-9a-f]{32}\Z', re.I)
    c = self.db.cursor()
    c.execute("SELECT id FROM keystone.project WHERE name = %s", project)
    tenant_id = c.fetchone()[0]
    if re.match(uuid_re, tenant_id):
      return tenant_id
    else:
      return None

  """
  Retrieve list of non-default quotas from database for the project
  """
  def _get_current_quota(self, component, tenant_id):
    self.db.select_db(component)
    c = self.db.cursor()
    c.execute("SELECT resource, hard_limit FROM quotas WHERE project_id = %s AND deleted = 0", tenant_id)
    current_quota = c.fetchall()
    return current_quota

  def run(self):
    for component in config:
      for project in config[component]:
        tenant_id = self._get_tenant_id(project)
        if tenant_id is not None:
          resources = config[component][project]
          current_quota = self._get_current_quota(component, tenant_id)
          configured_quota = []
          quota_cmd = [component, 'quota-update']
          """ Construct list of configured quota for comparison with current quota """
          for resource in resources:
            configured_quota.append((resource, config[component][project][resource],))
            """ Construct nova/cinder quota-update command in case we need it """
            quota_cmd.append('--' + string.replace(resource, '_', '-'))
            quota_cmd.append(str(config[component][project][resource]))
          if cmp(current_quota, tuple(configured_quota)) != 0:
            [arg for l in list(configured_quota) for arg in l]
            quota_cmd.append(tenant_id)
            process = subprocess.Popen(quota_cmd)
            process.communicate()
            if process.returncode != 0:
              sys.exit('Unable to update quota: ' + str(quota_cmd))

if __name__ == '__main__':
  config = yaml.load(open( '/usr/local/etc/os-quota.yml', 'r'))
  quota = OSQuota(config).run()
