resource "oci_containerengine_cluster" "oke_cluster_virtual" {
  compartment_id     = var.compartment_id
  vcn_id             = var.vcn_id
  kubernetes_version = var.kubernetes_version
  name               = var.cluster_name
  type               = var.cluster_type
  cluster_pod_network_options {
    cni_type = var.cni_type
  }

  endpoint_config {
    is_public_ip_enabled = true
    nsg_ids              = []
    subnet_id            = var.api_public_subnet_id
  }

  options {
    service_lb_subnet_ids = [var.lb_public_subnet_id]
    add_ons {
      is_kubernetes_dashboard_enabled = true
      is_tiller_enabled               = true
    }
  }
}

resource "oci_containerengine_virtual_node_pool" "oke_virtual_node_pool" {
  compartment_id = var.compartment_id
  cluster_id     = oci_containerengine_cluster.oke_cluster_virtual.id
  display_name   = "oke-dev-virtual-node-pool"

  placement_configurations {
    availability_domain = "lpZJ:US-ASHBURN-AD-1"
    fault_domain        = ["FAULT-DOMAIN-1"]
    subnet_id           = var.private_subnet_id
  }

  placement_configurations {
    availability_domain = "lpZJ:US-ASHBURN-AD-2"
    fault_domain        = ["FAULT-DOMAIN-1"]
    subnet_id           = var.private_subnet_id
  }

  placement_configurations {
    availability_domain = "lpZJ:US-ASHBURN-AD-3"
    fault_domain        = ["FAULT-DOMAIN-1"]
    subnet_id           = var.private_subnet_id
  }

  pod_configuration {
    nsg_ids  = []
    shape    = "Pod.Standard.E4.Flex"
    subnet_id = var.private_subnet_id
  }

  size = 3
}

resource "oci_containerengine_addon" "certmanager_addon" {
  addon_name                      = "CertManager"
  cluster_id                      = oci_containerengine_cluster.oke_cluster_virtual.id
  remove_addon_resources_on_delete = true
}

resource "oci_containerengine_addon" "clusterautoscaler_addon" {
  addon_name                      = "ClusterAutoscaler"
  cluster_id                      = oci_containerengine_cluster.oke_cluster_virtual.id
  configurations {
    key   = "nodes"
    value = "3:10:virtualNodePoolId:${oci_containerengine_virtual_node_pool.oke_virtual_node_pool.id}"
  }
  remove_addon_resources_on_delete = true
}

resource "oci_containerengine_addon" "metricsserver_addon" {
  addon_name                      = "KubernetesMetricsServer"
  cluster_id                      = oci_containerengine_cluster.oke_cluster_virtual.id
  remove_addon_resources_on_delete = true
  depends_on                      = [oci_containerengine_addon.certmanager_addon]
}

resource "oci_containerengine_addon" "nativeingress_addon" {
  addon_name                      = "NativeIngressController"
  cluster_id                      = oci_containerengine_cluster.oke_cluster_virtual.id
  configurations {
    key   = "compartmentId"
    value = var.compartment_id
  }
  configurations {
    key   = "loadBalancerSubnetId"
    value = var.lb_public_subnet_id
  }
  remove_addon_resources_on_delete = true
}

# Dynamic Group for Virtual Nodes
resource "oci_identity_dynamic_group" "virtual_nodes_dynamic_group" {
  compartment_id = var.tenancy_id
  name           = "virtual-nodes-dynamic-group"
  description    = "Dynamic group for virtual nodes"

  matching_rule = <<EOF
ALL {resource.type = 'virtualnode'}
EOF
}

# IAM Policy for Virtual Nodes
resource "oci_identity_policy" "virtual_nodes_policy" {
  compartment_id = var.tenancy_id
  name           = "virtual-nodes-policy"
  description    = "Policy for virtual nodes to operate in the specified compartment"

  statements = [
    "Allow dynamic-group virtual-nodes-dynamic-group to manage instance-family in compartment ${var.compartment_name} where ALL {request.principal.type='virtualnode', request.operation='CreateContainerInstance', request.principal.subnet=target.subnet.id}",
    "Allow dynamic-group virtual-nodes-dynamic-group to manage vnics in compartment ${var.compartment_name} where ALL {request.principal.type='virtualnode', request.operation='CreateContainerInstance', request.principal.subnet=target.subnet.id}",
    "Allow dynamic-group virtual-nodes-dynamic-group to manage network-security-group in compartment ${var.compartment_name} where ALL {request.principal.type='virtualnode', request.operation='CreateContainerInstance'}"
  ]
}

output "oke_cluster_virtual_id" {
  value = oci_containerengine_cluster.oke_cluster_virtual.id
}

output "oke_virtual_node_pool_id" {
  value = oci_containerengine_virtual_node_pool.oke_virtual_node_pool.id
}
