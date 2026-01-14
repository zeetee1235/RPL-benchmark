#!/usr/bin/env python3
"""Generate a Cooja .csc for a root + N senders experiment.

This keeps CLI reproducibility by fixing positions and simulation timing.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

EEPROM_B64 = (
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
)


def mote_block(mote_id: int, x: float, y: float, mote_type: str) -> str:
    return f"""    <mote>
      <interface_config>
        org.contikios.cooja.interfaces.Position
        <x>{x:.1f}</x>
        <y>{y:.1f}</y>
        <z>0.0</z>
      </interface_config>
      <interface_config>
        org.contikios.cooja.contikimote.interfaces.ContikiMoteID
        <id>{mote_id}</id>
      </interface_config>
      <interface_config>
        org.contikios.cooja.contikimote.interfaces.ContikiRadio
        <bitrate>250.0</bitrate>
      </interface_config>
      <interface_config>
        org.contikios.cooja.contikimote.interfaces.ContikiEEPROM
        <eeprom>{EEPROM_B64}</eeprom>
      </interface_config>
      <motetype_identifier>{mote_type}</motetype_identifier>
    </mote>
"""


def generate_positions(count: int, spacing: float, start_x: float, start_y: float) -> list[tuple[float, float]]:
    if count <= 0:
        return []
    cols = int(math.ceil(math.sqrt(count)))
    rows = int(math.ceil(count / cols))
    positions: list[tuple[float, float]] = []
    for r in range(rows):
        for c in range(cols):
            if len(positions) >= count:
                break
            x = start_x + c * spacing
            y = start_y + r * spacing
            positions.append((x, y))
    return positions


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate .csc for rpl-benchmark experiments")
    parser.add_argument("--root-dir", required=True, help="Absolute path to rpl-benchmark")
    parser.add_argument("--senders", type=int, default=3, help="Number of sender motes")
    parser.add_argument("--seed", type=int, default=1, help="Cooja random seed")
    parser.add_argument("--make-routing", default="MAKE_ROUTING_RPL_LITE", help="MAKE_ROUTING value")
    parser.add_argument("--send-interval", type=int, default=10, help="Sender interval seconds")
    parser.add_argument("--sim-time-ms", type=int, default=600000, help="Simulation time in ms")
    parser.add_argument("--tx-range", type=float, default=60.0, help="UDGM transmit range")
    parser.add_argument("--int-range", type=float, default=100.0, help="UDGM interference range")
    parser.add_argument("--success-tx", type=float, default=1.0, help="UDGM success_ratio_tx")
    parser.add_argument("--success-rx", type=float, default=1.0, help="UDGM success_ratio_rx")
    parser.add_argument("--brpl", action="store_true", help="Enable BRPL mode")
    parser.add_argument("--out", required=True, help="Output .csc path")
    args = parser.parse_args()

    root_dir = Path(args.root_dir).resolve()
    sim_time_ms = args.sim_time_ms

    positions = generate_positions(args.senders, spacing=25.0, start_x=60.0, start_y=40.0)

    motes = []
    motes.append(mote_block(1, 30.0, 60.0, "root"))
    for idx, (x, y) in enumerate(positions, start=2):
        motes.append(mote_block(idx, x, y, "sender"))

    motes_block = "".join(motes)

    # Script format matching working brpl_minimal.csc
    script = (
        f"TIMEOUT({sim_time_ms}, log.testOK());&#xD;\n"
        "log.log(\"Simulation started\\n\");&#xD;\n"
        "&#xD;\n"
        "while(true) {&#xD;\n"
        "  log.log(time + \" \" + id + \" \" + msg + \"\\n\");&#xD;\n"
        "  YIELD();&#xD;\n"
        "}&#xD;\n"
    )

    defines = f"SEND_INTERVAL_SECONDS={args.send_interval}"
    if args.brpl:
        defines += " BRPL_MODE=1"

    csc = f"""<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<simconf>
  <simulation>
    <title>rpl-benchmark stress RPL + UDP</title>
    <randomseed>{args.seed}</randomseed>
    <motedelay_us>1000000</motedelay_us>
    <radiomedium>
      org.contikios.cooja.radiomediums.UDGM
      <transmitting_range>{args.tx_range}</transmitting_range>
      <interference_range>{args.int_range}</interference_range>
      <success_ratio_tx>{args.success_tx}</success_ratio_tx>
      <success_ratio_rx>{args.success_rx}</success_ratio_rx>
    </radiomedium>
    <events>
      <logoutput>40000</logoutput>
    </events>
    <motetype>
      org.contikios.cooja.contikimote.ContikiMoteType
      <identifier>root</identifier>
      <description>Receiver Root</description>
      <source>{root_dir}/receiver_root.c</source>
      <commands>make -C {root_dir} receiver_root.cooja TARGET=cooja MAKE_ROUTING={args.make_routing} DEFINES=\"{defines}\"</commands>
      <moteinterface>org.contikios.cooja.interfaces.Position</moteinterface>
      <moteinterface>org.contikios.cooja.interfaces.Battery</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiVib</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiMoteID</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiRS232</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiBeeper</moteinterface>
      <moteinterface>org.contikios.cooja.interfaces.RimeAddress</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiIPAddress</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiRadio</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiButton</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiPIR</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiClock</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiLED</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiCFS</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiEEPROM</moteinterface>
      <moteinterface>org.contikios.cooja.interfaces.Mote2MoteRelations</moteinterface>
      <moteinterface>org.contikios.cooja.interfaces.MoteAttributes</moteinterface>
    </motetype>
    <motetype>
      org.contikios.cooja.contikimote.ContikiMoteType
      <identifier>sender</identifier>
      <description>Sensor Sender</description>
      <source>{root_dir}/sender.c</source>
      <commands>make -C {root_dir} sender.cooja TARGET=cooja MAKE_ROUTING={args.make_routing} DEFINES=\"{defines}\"</commands>
      <moteinterface>org.contikios.cooja.interfaces.Position</moteinterface>
      <moteinterface>org.contikios.cooja.interfaces.Battery</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiVib</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiMoteID</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiRS232</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiBeeper</moteinterface>
      <moteinterface>org.contikios.cooja.interfaces.RimeAddress</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiIPAddress</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiRadio</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiButton</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiPIR</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiClock</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiLED</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiCFS</moteinterface>
      <moteinterface>org.contikios.cooja.contikimote.interfaces.ContikiEEPROM</moteinterface>
      <moteinterface>org.contikios.cooja.interfaces.Mote2MoteRelations</moteinterface>
      <moteinterface>org.contikios.cooja.interfaces.MoteAttributes</moteinterface>
    </motetype>
{motes_block}  </simulation>
  <plugin>
    org.contikios.cooja.plugins.ScriptRunner
    <plugin_config>
      <script>{script}</script>
      <active>true</active>
    </plugin_config>
    <width>600</width>
    <z>1</z>
    <height>700</height>
    <location_x>400</location_x>
    <location_y>0</location_y>
  </plugin>
</simconf>
"""

    out_path = Path(args.out)
    out_path.write_text(csc)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
