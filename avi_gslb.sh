controller_ip=$(yq e 'select(.kind == "AKODeploymentConfig").spec.controller' /home/kubo/akodeploymentconfig.yaml)
username=$(yq e 'select(.metadata.name == "controller-credentials").data.username' /home/kubo/akodeploymentconfig.yaml | base64 -d)
password=$(yq e 'select(.metadata.name == "controller-credentials").data.password' /home/kubo/akodeploymentconfig.yaml | base64 -d)

mkdir /home/kubo/avi-gslb
cat > /home/kubo/avi-gslb/cluster_uuid.txt << EOF
show cluster
EOF

cluster_uuid=$(avi_shell --address $controller_ip --user $username --password $password  --file /home/kubo/avi-gslb/cluster_uuid.txt  --json | jq .uuid)


#initial configuration - license update, default segroup update, segroup creation, vsip creation, virtualservice creation
cat > /home/kubo/avi-gslb/avi_configure.txt << EOF
configure systemconfiguration default_license_tier enterprise
save
configure serviceenginegroup Default-Group
max_vs_per_se 30
save
configure serviceenginegroup appengine
max_se 1
max_vs_per_se 30
save

configure vsvip appengine
vip
vip_id 1
enabled
auto_allocate_ip
ipam_network_subnet
network_ref port-group-vlan-100
subnet 192.168.116.0/24
save
placement_networks
network_ref port-group-vlan-100
subnet 192.168.116.0/24
save
save
save

configure virtualservice appengine
application_profile_ref System-DNS
network_profile_ref System-UDP-Per-Pkt
vsvip_ref appengine
se_group_ref appengine
services
port 53
save
save
EOF

avi_shell --address $controller_ip  --user $username --password $password --file /home/kubo/avi-gslb/avi_configure.txt

cat > /home/kubo/avi-gslb/virtualservice.txt << EOF
show virtualservice appengine
EOF

virtualservice_uuid=$(avi_shell --address $controller_ip  --user $username --password $password --file /home/kubo/avi-gslb/virtualservice.txt  --json | jq .uuid)
virtualservice_ip=$(avi_shell --address $controller_ip  --user $username --password $password --file /home/kubo/avi-gslb/virtualservice.txt  --json | jq .vsvip_ref_data.vip[0].ip_address.addr | tr -d '"')
#gslb site configuration
cat > /home/kubo/avi-gslb/avi_gslb_site.txt << EOF
configure gslb Default
leader_cluster_uuid $cluster_uuid
dns_configs
domain_name appengine.tanzu.io
save
sites
name appengine
cluster_uuid $cluster_uuid
username $username
password $password
member_type GSLB_ACTIVE_MEMBER 
ip_addresses $controller_ip
port 443
dns_vses
dns_vs_uuid $virtualservice_uuid
domain_names appengine.tanzu.io
save
save
save
EOF

avi_shell --address $controller_ip  --user $username --password $password --file /home/kubo/avi-gslb/avi_gslb_site.txt

cat > /home/kubo/avi-gslb/se.txt << EOF
show serviceengine
EOF

echo "waiting for service engine to be up"
serviceengine_status=$(avi_shell --address 192.168.111.106 --user admin --password 'Admin!23' --file /home/kubo/avi-gslb/se.txt | grep appengine | grep OPER_UP)
while [ -z "$serviceengine_status" ];
do
  serviceengine_status=$(avi_shell --address 192.168.111.106 --user admin --password 'Admin!23' --file /home/kubo/avi-gslb/se.txt | grep appengine | grep OPER_UP)
  sleep 60
  echo "waiting"
done
echo "avi-gslb configured"

sudo echo "server=/appengine.tanzu.io/$virtualservice_ip" >> /etc/dnsmasq.d/vlan-dhcp-dns.conf
sudo systemctl restart dnsmasq