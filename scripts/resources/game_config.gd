class_name GameConfig
extends Resource
## All run difficulty / threat tuning in ONE editor-editable asset. Assign a .tres to the
## Game node's `config` slot (see game.tscn) and tune in the Inspector — no code editing.
## This is the "editor-first" home for how hard / scary a run is.
##
## Every system the spec added (power outage, watcher anger, flashlight battery, keycard,
## capacitor, stun) reads its numbers from HERE, so balancing is done entirely in-editor.

@export_group("Threat")
@export var watcher_count := 1            ## how many figures stalk the facility
@export var watcher_speed := 2.4          ## creep speed (m/s) when unobserved
@export var watcher_accel := 6.0          ## how fast it ramps to full speed
@export var catch_distance := 1.15        ## reach -> downs a player
@export var danger_range := 8.0           ## moving figure within this -> vignette + heartbeat

@export_group("Watcher anger (late-game escalation)")
## After this many seconds the watcher gets ANGRY: gaze no longer fully freezes it (it keeps
## creeping, just slower, while watched), it speeds up, and the eye burns. The thrown cellphone
## becomes the only hard stop. Set very high to effectively disable the escalation.
@export var anger_time := 600.0           ## 10 minutes by default
@export var anger_speed_mult := 1.6       ## speed multiplier once angry
@export var anger_watched_speed := 0.9    ## m/s it still creeps at WHILE being looked at, when angry
@export var stun_time := 6.0              ## seconds a thrown phone freezes the watcher solid

@export_group("Power outage")
@export var outage_enabled := true
@export var outage_first_delay := 75.0    ## seconds into the run before the FIRST outage can hit
@export var outage_interval := 90.0       ## avg seconds between outages after the first
@export var outage_interval_jitter := 30.0 ## +/- randomisation on the interval
@export var outage_ambient_energy := 0.06 ## environment ambient while blacked out (very dark)
@export var outage_watcher_speed_mult := 1.35 ## the dark makes it bolder
@export var outage_max_duration := 45.0   ## auto-restore failsafe if nobody hits the red button

@export_group("Flashlight")
@export var flashlight_enabled := true
@export var flashlight_drain := 0.018     ## battery fraction drained per second while ON (0..1)
@export var flashlight_recharge := 0.0    ## passive recharge/sec while OFF (0 = none; find batteries)
@export var flashlight_energy := 6.0      ## brightness of the beam
@export var flashlight_range := 24.0
@export var flashlight_angle := 26.0      ## tight cone (a real torch, not a floodlight)

@export_group("Smoking (cigarette)")
@export var cig_calm_time := 7.0          ## seconds of effect per cig
@export var cig_stamina_restore := 1.0    ## blink-stamina restored when you light up (0..1)
@export var cig_count := 3                ## cigs in a fresh pack

@export_group("Objectives — relay / breakers / valve")
@export var relay_charge_rate := 0.16     ## relay charge/sec while cranking (lower = longer hold)
@export var relay_decay_rate := 0.13      ## charge bled/sec when you let go (higher = punishing)
@export var switch_pull_time := 0.7       ## seconds of committed holding to throw one breaker
@export var lever_resistance := 1.0       ## global multiplier on how hard levers are to pull (>1 = heavier)
@export var valve_turns := 3.0            ## full rotations to fully open a valve
@export var valve_decay := 0.35           ## turns/sec lost when you stop cranking the valve
@export var require_final_lockdown := true ## a final task in the deepest room gates the escape

@export_group("Capacitor transport")
@export var capacitor_count := 2          ## how many capacitors must be carried to the socket bank
@export var capacitor_carry_slow := 0.62  ## movement multiplier while lugging a capacitor

@export_group("Keycard doors")
@export var keycard_doors_enabled := true ## locked doors that force routes through the facility
