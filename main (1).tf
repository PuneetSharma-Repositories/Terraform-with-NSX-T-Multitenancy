# NSX-T Manager Credentials
provider "nsxt" {
  host                  = "192.168.50.1"
  username              = "admin"
  password              = "VMware1!!VMware1!!"
  allow_unverified_ssl  = true
  max_retries           = 10
  retry_min_delay       = 500
  retry_max_delay       = 5000
  retry_on_status_codes = [429]
}

#******************************************************************************
#***********Creating Tier-0 Gateway via Terraform******************************
#******************************************************************************

data "nsxt_policy_transport_zone" "vlan_tz" {
  display_name               = "nsx-vlan-transportzone"
}

data "nsxt_policy_edge_cluster" "edge_cluster" {
  display_name               = "Edge-Cluster-01"
}
data "nsxt_policy_edge_node" "edge_node_1" {
  edge_cluster_path          = data.nsxt_policy_edge_cluster.edge_cluster.path
  display_name               = "Edge-01"
}
#******************************************************************************
#********Creating Uplink Vlan Segment for Tier-0 gateway***********************
#******************************************************************************

resource "nsxt_policy_vlan_segment" "vlan-100" {
  display_name        = "vlan-100"
  description         = "Created for Tier-0 interfaces uplink interfaces"
  transport_zone_path = data.nsxt_policy_transport_zone.vlan_tz.path
  vlan_ids            = [100]
}


#******************************************************************************
#**********************Creating Tier-0 Gateway*********************************
#******************************************************************************


resource "nsxt_policy_tier0_gateway" "tier0_gw" {
  description              = "Tier-0 provisioned by Terraform"
  display_name             = "Tier0-gw"
  default_rule_logging     = false
  enable_firewall          = true
  force_whitelisting       = false
  ha_mode                  = "ACTIVE_ACTIVE"
  edge_cluster_path        = data.nsxt_policy_edge_cluster.edge_cluster.path
  bgp_config {
    ecmp                   = true
    local_as_num           = "100"
    inter_sr_ibgp          = true
    multipath_relax        = true
 }
  redistribution_config {
    enabled               = true
    rule {
      name                = "t0-route-redistribution"
      types               = ["TIER1_LB_VIP", "TIER1_CONNECTED", "TIER1_SERVICE_INTERFACE", "TIER1_NAT", "TIER1_LB_SNAT"]
    }
  }
}

#******************************************************************************
#********Creating Tier-0 Gateway Uplink Interfaces*****************************
#******************************************************************************

resource "nsxt_policy_tier0_gateway_interface" "edge1-uplink-1" {
  display_name           = "edge1-uplink-1"
  type                   = "EXTERNAL"
  description            = "Vlan-100 interface on Edge-1"
  gateway_path           = nsxt_policy_tier0_gateway.tier0_gw.path
  segment_path           = nsxt_policy_vlan_segment.vlan-100.path
  edge_node_path         = data.nsxt_policy_edge_node.edge_node_1.path
  subnets                = ["192.168.100.2/24"]
  mtu                    = 1500
}


#******************************************************************************
#********Creating BGP on Tier-0 gateway for uplink*****************************
#******************************************************************************

resource "nsxt_policy_bgp_neighbor" "router" {
  display_name     = "BGP to Tor-A"
  description      = "Terraform provisioned BGP Neighbor Configuration"
  bgp_path         = nsxt_policy_tier0_gateway.tier0_gw.bgp_config.0.path
  neighbor_address = "192.168.100.1"
  remote_as_num    = "200"
  hold_down_time   = "180"
  keep_alive_time  = "60"
  source_addresses = ["192.168.100.2"]
}
#******************************************************************************
#*************Creating Mutli-tenancy using Terraform***************************
#******************************************************************************
resource "nsxt_policy_project" "ProjectA" {
  display_name        = "ProjectA"
  description         = "Terraform provisioned ProjectA"
  short_id            = "ProjA"
  tier0_gateway_paths = [nsxt_policy_tier0_gateway.tier0_gw.path]
  edge_cluster_paths  = data.nsxt_policy_edge_cluster.edge_cluster.path
}
resource "nsxt_policy_project" "ProjectB" {
  display_name        = "ProjectB"
  description         = "Terraform provisioned ProjectB"
  short_id            = "ProjB"
  tier0_gateway_paths = [nsxt_policy_tier0_gateway.tier0_gw.path]
}

data "nsxt_policy_transport_zone" "overlay_tz" {
     display_name   = "nsx-overlay-transportzone"
}
data "nsxt_policy_tier0_gateway" "T0-GW-01" {
     display_name   = "Tier0-gw"
}
data "nsxt_policy_project" "projecta" {
  display_name     = "ProjectA"
}
data "nsxt_policy_project" "projectb" {
  display_name     = "ProjectB"
}
#******************************************************************************
#********Creating Tier-1 Gateway and Segments for ProjectA*********************
#******************************************************************************

resource "nsxt_policy_tier1_gateway" "tier1_gw" {
  context {
    project_id = data.nsxt_policy_project.projecta.id
  }
  description               = "Tier-1 provisioned by Terraform"
  display_name              = "T1-MT-PROJA"
  nsx_id                    = "predefined_id"
  failover_mode             = "PREEMPTIVE"
  default_rule_logging      = "false"
  enable_firewall           = "true"
  enable_standby_relocation = "false"
  tier0_path                = data.nsxt_policy_tier0_gateway.T0-GW-01.path
  route_advertisement_types = ["TIER1_STATIC_ROUTES", "TIER1_CONNECTED"]
  pool_allocation           = "ROUTING"
}
resource "nsxt_policy_segment" "segment1" {
  context {
    project_id = data.nsxt_policy_project.projecta.id
  }
  display_name      = "ProjA-DEV"
  description       = "Terraform provisioned Segment"
  connectivity_path = nsxt_policy_tier1_gateway.tier1_gw.path

  subnet {
    cidr        = "10.1.1.1/24"
        }
}

#******************************************************************************
#********Creating Tier-1 Gateway and Segment for ProjectB**********************
#******************************************************************************


resource "nsxt_policy_tier1_gateway" "tier1_gw2" {
  context {
    project_id = data.nsxt_policy_project.projectb.id
  }
  description               = "Tier-1 provisioned by Terraform"
  display_name              = "T1-MT-PROJB"
  nsx_id                    = "predefined_id"
  failover_mode             = "PREEMPTIVE"
  default_rule_logging      = "false"
  enable_firewall           = "true"
  enable_standby_relocation = "false"
  tier0_path                = data.nsxt_policy_tier0_gateway.T0-GW-01.path
  route_advertisement_types = ["TIER1_STATIC_ROUTES", "TIER1_CONNECTED"]
  pool_allocation           = "ROUTING"
}
resource "nsxt_policy_segment" "segment2" {
  context {
    project_id = data.nsxt_policy_project.projectb.id
  }
  display_name      = "ProjB-DEV"
  description       = "Terraform provisioned Segment"
  connectivity_path = nsxt_policy_tier1_gateway.tier1_gw2.path

  subnet {
    cidr        = "20.1.1.1/24"
        }
}
