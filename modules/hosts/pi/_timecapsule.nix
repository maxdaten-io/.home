{
  ...
}:
let
  mount = "/mnt/timecapsule";
in
{

  # fileSystems.mount = {
  #   device = "/dev/disk/by-label/TIMECAPSULE";
  #   fsType = "ext4";
  #   # options = ["uid=${config.users.groups.timecapsule.uid},gid=${config.users.groups.timecapsule.gid}"];
  # };

  users = {
    groups.timemachine = {
      gid = 2500;
    };

    users.timemachine = {
      isSystemUser = true;
      uid = 2500;
      group = "timemachine";
      home = mount;
    };
  };

  services.samba = {
    enable = true;
    openFirewall = true;
    shares = {
      timemachine = {
        path = mount;
        "valid users" = "jloos @timemachine";
        "force user" = "timemachine";
        "force group" = "timemachine";
        "ea support" = "yes";
        browseable = "yes";
        public = "no";
        writeable = "yes";
        "fruit:aapl" = "yes";
        "fruit:metadata" = "stream";
        "fruit:time machine" = "yes";
        "fruit:time machine max size" = "1500G";
        "fruit:posix_rename" = "yes";
        "fruit:veto_appledouble" = "no";
        "fruit:nfs_aces" = "no";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
      };
    };
  };

  # https://sterba.dev/posts/raspi-as-time-capsule/
  services.avahi.extraServiceFiles.timecapsule = ''
    <?xml version="1.0" standalone='no'?><!--*-nxml-*-->
    <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
    <service-group>
      <name replace-wildcards="yes">%h</name>
      <service>
        <type>_smb._tcp</type>
        <port>445</port>
      </service>
      <service>
        <type>_device-info._tcp</type>
        <txt-record>model=TimeCapsule8,119</txt-record>
      </service>
      <service>
        <type>_adisk._tcp</type>
        <txt-record>dk0=adVN=Timemachine,adVF=0x82</txt-record>
        <txt-record>sys=waMa=0,sys=adVF=0x100</txt-record>
      </service>
    </service-group>
  '';
}
