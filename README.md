# Mac AWS CLI VPN Client

An alternate MacOS VPN Client for AWS.

## Usage

1. [Install](#installation) a patched version of OpenVPN
2. Place your AWS VPN configuration in `./configs`
3. Pass the name of your conf to the client script.

Assuming you have a VPN config saved at `./configs/staging.conf`, run the following:

```sh
aws-connect.sh staging
```

## Caution

This project is based on a proof of concept and requires a patched version of OpenVPN.

Currently the **latest supported version is 2.5.1**. Patches for newer versions could be
created easily enough. But I don't want to deal with the maintenance headache of that,
so if you want that, clone the repo, create the patch, modify the brew formula and build
it yourself.

Obviously, there are downsides to this. Proceed with an appropriate level of caution.

## Installation

Using this client requires a patched version of OpenVPN. It is up to you to ensure that
exists. Conveniently, this also comes with a Homebrew formula to build a patched
version.

> [Caution]: This *will* conflict with an already-installed version of OpenVPN. Proceed at
> your own risk!

```sh
brew install --formula openvpn-aws.rb
```

By default, that will link `openvpn` to the built `openvpn-aws` executable. You can
unlink it, then link a non-patched version for general usage. You will then need to pass
the path to the patched version into the client script.

## Motivation

The first-party [AWS VPN Client](https://aws.amazon.com/vpn/client-vpn-download/) sucks.
Primarily for me this is because it:

1. Doesn't natively support Apple Silicon
2. Only allows connection to a single VPN at a time
3. Has a janky, always-open (no menu bar) UI.
4. Leave it connected, and you'll come back to your computer with a bunch of open tabs.

So I went out on a quest to find a different client. Turns out, the AWS client uses
proprietary changes to OpenVPN that are baked into their client. Viscosity [doesn't want
to incorporate them][viscosity-says-no] (which seems reasonable).

Thankfully, Alex Samorukov had reverse-engineered their changes. And [put together a
PoC](https://github.com/samm-git/aws-vpn-client).

Everything I needed was there.

## TODO

Wouldn't it be nice if I did the following?

- Support newer versions of OpenVPN
- Wrap it in a menu bar utility

---

[viscosity-says-no]: https://www.sparklabs.com/forum/viewtopic.php?t=3144#p10090
