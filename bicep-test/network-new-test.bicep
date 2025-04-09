import {pow2_or_0,subnet_octets} from '../bicep/network-new.bicep'

/* Testing pow2_or_0 function, fixes issue #220*/

assert pow2toNeg1000 = pow2_or_0(-1000) == 0
assert pow2toNeg2 = pow2_or_0(-2) == 0
assert pow2toNeg1 = pow2_or_0(-1) == 0
assert pow2to0 = pow2_or_0(0) == 1 
assert pow2to1 = pow2_or_0(1) == 2
assert pow2to2 = pow2_or_0(2) == 4
assert pow2to3 = pow2_or_0(3) == 8
assert pow2to4 = pow2_or_0(4) == 16
assert pow2to5 = pow2_or_0(5) == 32
assert pow2to6 = pow2_or_0(6) == 64
assert pow2to7 = pow2_or_0(7) == 128

/* Testing subnet_octets function, fixes issue #220*/

var base_octets = {
  cyclecloud: { //cyclecloud
    o3: 0
    o4: 0
    cidr: 29
  }
  scheduler: { //admin
    o3: 0
    o4: 16
    cidr: 28
  }
  bastion: {
    o3: 0
    o4: 64
    cidr: 26
  }
}

var base_octets_non24 = union(base_octets,{
  netapp: {
    o3: 0
    o4: 32
    cidr: 28
  }
  lustre: {
    o3: 0
    o4: 128
    cidr: 26
  }
  database: {
    o3: 0
    o4: 224
    cidr: 28
  }
}) 

assert cidr19 = subnet_octets(19) ==  union(base_octets_non24,{
  compute: {
    o3: 16
    o4: 0
    cidr: 20
  }
})

assert cidr20 = subnet_octets(20) ==  union(base_octets_non24,{
  compute: {
    o3: 8
    o4: 0
    cidr: 21
  }
})

assert cidr21 = subnet_octets(21) ==  union(base_octets_non24,{
  compute: {
    o3: 4
    o4: 0
    cidr: 22
  }
})

assert cidr22 = subnet_octets(22) ==  union(base_octets_non24,{
  compute: {
    o3: 2
    o4: 0
    cidr: 23
  }
})

assert cidr23 = subnet_octets(23) ==  union(base_octets_non24,{
  compute: {
    o3: 1
    o4: 0
    cidr: 24
  }
})

assert cidr24 = subnet_octets(24) ==  union(base_octets,{
  netapp: {
    o3: 0
    o4: 32
    cidr: 29
  }
  lustre: {
    o3: 0
    o4: 48
    cidr: 28
  }
  database: {
    o3: 0
    o4: 40
    cidr: 29
  }
  compute: {
    o3: 0
    o4: 128
    cidr: 25
  }
})
