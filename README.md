# Mac AWS CLI VPN Client

An alternate MacOS VPN Client for AWS.

## Setup

Before using this client, there are a couple steps you need to take first:

1. [Install](#installation) go, openssl, and the official **AWS VPN Client**
2. Build the go server (`go build`)
3. Place your AWS VPN configuration in `./configs` by name that will be passed to the
   script. For example, `./configs/prod.conf`.

> [!IMPORTANT]
> This client **requires the official AWS VPN Client to be installed**. It does not
> ship or build its own OpenVPN; instead it drives the patched OpenVPN (`acvc-openvpn`)
> bundled inside the AWS VPN Client app. AWS keeps that binary in sync with their
> proprietary SAML control-channel protocol, so we don't have to maintain a patch.
> See [Installation](#installation).

## Usage

The script is called `aws-connect.sh` and takes one required argument: the name of your config.

Assuming you have a VPN config saved at `./configs/staging.conf`, run the following:

```sh
aws-connect.sh staging
```

You may also ensure that you have an active aws sso session by passing the `-a` flag.
Helpful in case you, like me, always forget to do this before connecting to k8s.

By default the script uses the patched OpenVPN bundled with the official AWS VPN Client
(`acvc-openvpn`). If it isn't installed, the script will tell you and exit. If you have a
patched OpenVPN somewhere else, pass its path via the `-x` flag to override.

> [!TIP] You can *also* use this client on Linux, however it is not tested, and you need
> to build your own openvpn-aws client, or pull the `acvc-openvpn` binary out of the AWS
> client and point at it with `-x`.

## Caution

This project is based on a proof of concept and relies on a patched version of OpenVPN
that understands AWS's proprietary SAML auth.

Rather than maintain that patch ourselves, this client uses the `acvc-openvpn` binary
shipped inside the official AWS VPN Client. AWS keeps it current with their protocol.

> [!WARNING]
> Do **not** substitute a stock OpenVPN or a self-built patch on a newer OpenVPN release.
> The community `openvpn-v2.5.1-aws.patch` applied to OpenVPN 2.6.13+ mis-parses the
> `AUTH_FAILED`/`CRV1` SAML control message and aborts with a bogus
> `fatal buffer size error, size=<huge>` *before* the login URL is returned. The AWS
> client pins OpenVPN **2.6.12**, which is why driving its binary works.

## Installation

Install the official **AWS VPN Client** — this client drives the patched OpenVPN it
bundles:

```sh
brew install --cask aws-vpn-client
# or download from https://aws.amazon.com/vpn/client-vpn-download/
```

The script looks for the bundled binary at:

```
/Applications/AWS VPN Client/AWS VPN Client.app/Contents/Resources/openvpn/acvc-openvpn
```

You will also need `go` and `openssl` installed. Typically this is done by running:

```sh
brew install go openssl@3
```

> [!NOTE]
> A Homebrew formula (`Formula/openvpn-aws.rb`) that builds a patched OpenVPN 2.6.19 is
> kept in this repo for reference, but it is **not** used by default and currently
> triggers the `fatal buffer size error` described above. Prefer the AWS VPN Client.

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
- Wrap this up in a single rust executable, rather than bash + go + tempfiles, etc
  * Even better: Wrap it in a menu bar utility
- Incorporate some suggested improvements to the original repo
  * https://github.com/samm-git/aws-vpn-client/issues/17

---

[viscosity-says-no]: https://www.sparklabs.com/forum/viewtopic.php?t=3144#p10090
