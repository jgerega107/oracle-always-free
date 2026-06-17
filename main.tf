data "oci_identity_availability_domains" "this" {
  compartment_id = var.compartment_id
}

data "oci_core_images" "oracle_linux" {
  compartment_id           = var.compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = var.oracle_linux_version
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

locals {
  availability_domain = coalesce(var.availability_domain, data.oci_identity_availability_domains.this.availability_domains[0].name)
  tailscale_hostname  = coalesce(var.tailscale_hostname, var.name)
  tailscale_up_args = concat(
    [
      "--authkey=${var.tailscale_auth_key}",
      "--hostname=${local.tailscale_hostname}"
    ],
    var.tailscale_enable_ssh ? ["--ssh"] : []
  )
  cloud_init_users = concat(
    ["default"],
    var.create_admin_user ? [
      {
        name                = var.default_user
        groups              = "wheel"
        shell               = "/bin/bash"
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd         = true
        ssh_authorized_keys = [var.ssh_public_key]
      }
    ] : []
  )
  tailscale_cloud_init = "#cloud-config\n${yamlencode({
    package_update = true
    users          = local.cloud_init_users
    runcmd = [
      ["sh", "-c", "curl -fsSL https://tailscale.com/install.sh | sh"],
      ["sh", "-c", "tailscale up ${join(" ", local.tailscale_up_args)}"]
    ]
  })}"
  common_tags = merge(
    {
      managed-by = "tofu"
      module     = "oci-free-server"
    },
    var.freeform_tags
  )
}

resource "oci_core_vcn" "this" {
  compartment_id                   = var.compartment_id
  cidr_block                       = var.vcn_cidr
  display_name                     = "${var.name}-vcn"
  dns_label                        = replace(substr(var.name, 0, 15), "-", "")
  is_ipv6enabled                   = var.enable_ipv6
  is_oracle_gua_allocation_enabled = var.enable_ipv6
  freeform_tags                    = local.common_tags
}

resource "oci_core_default_security_list" "this" {
  manage_default_resource_id = oci_core_vcn.this.default_security_list_id
  display_name               = "${var.name}-default-security-list"
  freeform_tags              = local.common_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-igw"
  enabled        = true
  freeform_tags  = local.common_tags
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-public-routes"
  freeform_tags  = local.common_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }

  dynamic "route_rules" {
    for_each = var.enable_ipv6 ? [1] : []

    content {
      destination       = "::/0"
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_internet_gateway.this.id
    }
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name}-public-security-list"
  freeform_tags  = local.common_tags

  ingress_security_rules {
    protocol = "17"
    source   = "0.0.0.0/0"

    udp_options {
      min = var.tailscale_udp_port
      max = var.tailscale_udp_port
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = var.vcn_cidr

    icmp_options {
      type = 3
      code = 4
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.enable_ipv6 ? [1] : []

    content {
      protocol = "17"
      source   = "::/0"

      udp_options {
        min = var.tailscale_udp_port
        max = var.tailscale_udp_port
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = var.enable_ipv6 ? [1] : []

    content {
      protocol = "58"
      source   = "::/0"

      icmp_options {
        type = 2
        code = 0
      }
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  dynamic "egress_security_rules" {
    for_each = var.enable_ipv6 ? [1] : []

    content {
      protocol    = "all"
      destination = "::/0"
    }
  }
}

resource "oci_core_subnet" "public" {
  compartment_id            = var.compartment_id
  vcn_id                    = oci_core_vcn.this.id
  cidr_block                = var.subnet_cidr
  display_name              = "${var.name}-public-subnet"
  dns_label                 = "public"
  ipv6cidr_block            = var.enable_ipv6 ? cidrsubnet(oci_core_vcn.this.ipv6cidr_blocks[0], 8, var.ipv6_subnet_index) : null
  prohibit_internet_ingress = !(var.assign_public_ip || var.enable_ipv6)
  route_table_id            = oci_core_route_table.public.id
  security_list_ids         = [oci_core_security_list.public.id]
  freeform_tags             = local.common_tags
}

resource "oci_core_instance" "this" {
  compartment_id      = var.compartment_id
  availability_domain = local.availability_domain
  display_name        = var.name
  shape               = "VM.Standard.A1.Flex"
  freeform_tags       = local.common_tags

  shape_config {
    ocpus         = var.a1_ocpus
    memory_in_gbs = var.a1_memory_in_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_ipv6ip    = var.enable_ipv6
    assign_public_ip = var.assign_public_ip
    display_name     = "${var.name}-vnic"
    hostname_label   = replace(substr(var.name, 0, 15), "-", "")
    freeform_tags    = local.common_tags
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.oracle_linux.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(local.tailscale_cloud_init)
  }

  agent_config {
    is_management_disabled = true
    is_monitoring_disabled = true

    dynamic "plugins_config" {
      for_each = var.disable_agent_plugin_names

      content {
        name          = plugins_config.value
        desired_state = "DISABLED"
      }
    }
  }
}

resource "oci_budget_budget" "this" {
  compartment_id = var.compartment_id
  target_type    = "COMPARTMENT"
  targets        = [var.compartment_id]
  amount         = var.budget_amount
  reset_period   = "MONTHLY"
  display_name   = "${var.name}-cost-alert-budget"
  description    = "Budget used to alert when any actual OCI cost appears for ${var.name}."
  freeform_tags  = local.common_tags
}

resource "oci_budget_alert_rule" "any_cost" {
  budget_id      = oci_budget_budget.this.id
  display_name   = "${var.name}-any-cost-alert"
  description    = "Alerts when actual spend reaches at least ${var.budget_alert_threshold} USD."
  type           = "ACTUAL"
  threshold      = var.budget_alert_threshold
  threshold_type = "ABSOLUTE"
  recipients     = var.budget_alert_email
  message        = "OCI actual spend has reached at least ${var.budget_alert_threshold} USD for ${var.name}. Review your Always Free resources."
}
