# RenaultDiag

An iPhone diagnostic app for Renault cars, built around a Bluetooth ELM327 adapter (vLinker MC+).

## Why I built it

I tried several apps to connect to my car's OBD2 port. None of them worked properly, and none of them let me clear the warning messages on the dashboard. So I built my own app. Now it does everything I wanted.

## What it does

- **Fault scan across the whole car.** It talks to each Renault ECU directly (engine, ABS/ESP, airbag, body control, instrument cluster, power steering, parking brake…), not only the engine like generic OBD apps.
- **Clear fault codes, like a garage tool.** Per ECU or all at once. After clearing it re-reads the memory and tells you if a fault comes straight back, which means the problem is still there.
- **Safety checks.** It refuses to clear while the car is moving or the engine is running, warns about airbag and brake faults, and saves the fault list to a history before every clear.
- **Live data.** Engine speed, temperatures, boost, airflow, EGR, fuel and more, with graphs and CSV export. Exhaust and DPF sensors are shown when the car provides them, with a warning when a sensor stays at zero or does not move.
- **Vehicle info.** VIN, check-engine light, emissions readiness monitors, freeze frame, pending and permanent codes.
- **Renault value finder.** A read-only tool that lists the manufacturer-specific values an ECU will give, then records which ones move, to find data that standard OBD does not expose.
- **Console.** Every exchange with the adapter, shareable as a log for debugging.
- **Demo mode.** A simulated car with fake faults, to try the app without an adapter.

The app interface is in French.

## Tested on

- Renault Grand Scénic III (2013, 2.0 dCi), with a vGate vLinker MC+.
- iPhone 13 Pro.

Other Renault models on CAN should work, but have not been tried.

## Install

1. Open `ScenicDiag.xcodeproj` in Xcode (the project keeps its original internal name).
2. In Signing & Capabilities, pick your own team, and change the bundle identifier if needed.
3. Plug in your iPhone, select it, and press Run.
4. On the iPhone: Settings > General > VPN & Device Management, trust your developer certificate.

With a free Apple account, the app expires after 7 days; press Run again to reinstall.

In the app, connect to the adapter from the Connexion tab. Do not pair it in the iPhone's Bluetooth settings.

## Limitations

- Renault's own fault names (the DFxxx codes shown by Renault's dealer tool CLIP) are not public, so the app shows the standard code, the raw code and a generic description.
- It reads and clears faults. It does not write any configuration, code ECUs, or force DPF regenerations.
- Clearing a fault does not repair anything. If the warning comes back, the fault is real: get it checked, especially for airbag, brakes or engine.

## Development

The diagnostic logic lives in a Swift package with its own tests, which run without an iPhone:

```bash
cd Packages/DiagCore && swift test
```

## Credits

- ECU CAN address table from the [pyren](https://github.com/emtee40/pyren-OBD2) project.
- ELM327 initialisation sequences studied from [DDT4All](https://github.com/cedricp/ddt4all).

## Disclaimer

This is a personal, unofficial project. It is not affiliated with, endorsed by, or connected to Renault. Renault is a trademark of its owner. Use it at your own risk: you are responsible for what you do with your car.

## License

[MIT](LICENSE)
