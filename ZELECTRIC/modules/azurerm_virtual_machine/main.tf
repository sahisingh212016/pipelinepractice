variable "vms" {
  type = map(any)
}

data "azurerm_availability_set" "set" {
  for_each            = var.vms
  name                = each.value.availability_set_name
  resource_group_name = each.value.resource_group_name
}

data "azurerm_subnet" "subnet" {
  for_each             = var.vms
  name                 = each.value.subnet_name
  virtual_network_name = each.value.virtual_network_name
  resource_group_name  = each.value.resource_group_name
}

data "azurerm_key_vault" "kv" {
  for_each            = var.vms
  name                = each.value.kv_name
  resource_group_name = each.value.resource_group_name
}

resource "random_password" "apass" {
  for_each         = var.vms
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "azurerm_key_vault_secret" "password" {
  for_each     = var.vms
  name         = "${each.value.vm_name}-password"
  value        = random_password.apass[each.key].result
  key_vault_id = data.azurerm_key_vault.kv[each.key].id
}

resource "azurerm_public_ip" "pip" {
  for_each            = var.vms
  name                = "${each.value.vm_name}-pip"
  resource_group_name = each.value.resource_group_name
  location            = each.value.location
  allocation_method   = "Static"
}


resource "azurerm_network_security_group" "nsg" {
  for_each            = var.vms
  name                = "${each.value.vm_name}-nsg"
  location            = each.value.location
  resource_group_name = each.value.resource_group_name

  security_rule {
    name                       = "test123"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_network_interface" "nic" {
  for_each            = var.vms
  name                = each.value.nic_name
  location            = each.value.location
  resource_group_name = each.value.resource_group_name

  ip_configuration {
    name                          = "dhondhuips"
    subnet_id                     = data.azurerm_subnet.subnet[each.key].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip[each.key].id
  }
}

resource "azurerm_network_interface_security_group_association" "nicnsgassoc" {
  for_each                  = var.vms
  network_interface_id      = azurerm_network_interface.nic[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg[each.key].id
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each                        = var.vms
  name                            = each.value.vm_name
  resource_group_name             = each.value.resource_group_name
  location                        = each.value.location
  size                            = each.value.size
  availability_set_id             = data.azurerm_availability_set.set[each.key].id
  admin_username                  = "devopsadmin"
  admin_password                  = azurerm_key_vault_secret.password[each.key].value
  disable_password_authentication = false
  network_interface_ids           = [azurerm_network_interface.nic[each.key].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

