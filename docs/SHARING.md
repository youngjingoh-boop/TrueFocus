# Putting TrueFocus on someone else's devices

No App Store needed. Each person gets their own private space: their plan and notes never mix with yours unless one of you enters the other's link code, so **never link a friend's device with yours** — have them link their own iPhone and Mac to each other.

## iPhone: install from your Mac (simplest)

1. Plug their iPhone into your Mac. On the iPhone: *Trust This Computer*, then Settings ▸ Privacy & Security ▸ **Developer Mode** ▸ on (it restarts).
2. In Xcode pick the **TrueFocus** scheme and their iPhone as destination, Run. Xcode registers the phone to your team the first time.
3. On their iPhone: Settings ▸ General ▸ VPN & Device Management ▸ your developer profile ▸ *Trust*.
4. Walk them through [SETUP.md](SETUP.md) step 2.

A build installed this way runs for about a year (your provisioning profile's lifetime); re-run from Xcode to renew. Your developer account allows 100 iPhones per year.

## iPhone: TestFlight (no cable, invites by email)

Good once more than a couple of people use it. One extra step first: TestFlight builds use the **distribution** Family Controls entitlement, which Apple grants on request (developer.apple.com ▸ Account ▸ request *Family Controls (Distribution)* — the form asks what the app does; usually a few days). After it's approved: Product ▸ Archive ▸ Distribute ▸ TestFlight, add them as testers in App Store Connect. External testers need a quick beta review; builds last 90 days.

## Mac

Either Run **TrueFocusMac** on their Mac from Xcode, or export a copy you can send:

1. Product ▸ Archive (scheme TrueFocusMac) ▸ Distribute App ▸ **Direct Distribution** (Developer ID). Xcode signs and notarizes it.
2. Send them the exported `TrueFocus.app`; they drag it to Applications.

Then they do [SETUP.md](SETUP.md) step 3, and link their own iPhone and Mac with step 4.

## Their data

It lives in the same Supabase project as yours, in a separate space only their devices hold the key to, encrypted on their devices. You can see that rows exist (and roughly how many), not what's in them.
