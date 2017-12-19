require_relative 'bcpc'
include BCPC

def get_virtualbox_property(name)
  @_vbox_properties ||= begin
    out = %x[ VBoxManage list systemproperties ]
    lines = out.split("\n")
    pairs = lines.collect {|l|
      raw_key, val = l.split(':')
      key = raw_key.downcase.gsub(/ /,'_')
      [key, val.strip]
    }
    Hash[pairs]
  rescue Exception => e
    raise "Failed to enumerate Virtualbox properties: #{e}"
  end
  # Make sure to hard fail
  @_vbox_properties.fetch name
end

def generate_network_name(label)
  @vmdir ||=  get_virtualbox_property('default_machine_folder')
  mapping = {
    label: label,
    uid: Process.euid,
    virtualbox_vm_dir: @vmdir,
  }
  @g ||= NetworkIDGenerator.new
  id = @g.generate_id mapping
  [label, id].join('-')
end
