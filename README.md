# 🏰 Procedural AI Dungeon — Godot 4.3

A procedural dungeon generation system with AI-driven enemies, dynamic difficulty adjustment, and a full behavior tree framework. Built in Godot 4.3 with GDScript.

![Godot](https://img.shields.io/badge/Godot-4.3-478CBF?logo=godot-engine&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 🎯 Features

### Procedural Generation
- **BSP Tree Dungeon Generation** — Binary Space Partition creates balanced room layouts with configurable depth, room sizes, and split variance
- **Cellular Automata Caves** — Organic cave regions carved via CA rules (configurable birth/death thresholds, iteration count)
- **L-Shaped Corridors** — Sibling-paired corridor connections with door placement at room boundaries
- **Async Generation** — Non-blocking generation pipeline that yields each frame for large dungeons

### AI Systems
- **Behavior Trees** — Modular BT framework (Selector, Sequence, Condition, Action, Inverter, Repeat, Parallel nodes)
- **Perception System** — FOV-based visual detection with raycasted line-of-sight + auditory detection with loudness falloff
- **Steering Behaviors** — Craig Reynolds-style seek/flee/avoidance with obstacle raycasting
- **Agent Memory** — Temporal memory of last-seen positions with threat-level scoring and decay
- **Data-Driven Agents** — Enemy types defined via `AgentConfig` resources — no code changes needed for new variants

### AI Director
- **Dynamic Difficulty** — Real-time player performance evaluation (K/D, damage ratios) drives difficulty scaling
- **Intensity Curve Management** — Target intensity with automatic calm periods after spikes (L4D-inspired)
- **Smart Spawning** — Spawn point selection outside player FOV within configurable distance bands
- **Encounter Types** — Standard, pack, elite, and ambush encounters weighted by difficulty level

---

## 📂 Project Structure

```
godot-procedural-ai/
├── project.godot
├── scenes/
│   ├── main/          # Main game scene
│   ├── dungeon/       # Dungeon tilemap scenes
│   ├── agents/        # Enemy/player prefabs
│   └── ui/            # HUD and debug overlays
├── scripts/
│   ├── generation/
│   │   └── dungeon_generator.gd    # BSP + CA dungeon pipeline
│   ├── ai/
│   │   ├── ai_agent.gd             # Agent with BT integration
│   │   ├── ai_director.gd          # Dynamic difficulty system
│   │   ├── behavior_tree.gd        # BT node framework
│   │   ├── perception_component.gd # Vision + hearing
│   │   └── steering_component.gd   # Movement behaviors
│   ├── core/
│   │   ├── game_manager.gd         # A* nav + global state
│   │   ├── event_bus.gd            # Decoupled signal bus
│   │   ├── agent_config.gd         # Data-driven enemy configs
│   │   └── dungeon_data.gd         # Generation output container
│   └── utils/
├── resources/
│   ├── themes/        # DungeonTheme resources
│   └── agent_configs/ # Enemy type configurations
├── addons/
│   └── debug_overlay/ # Real-time AI state visualization
└── tests/             # Unit tests for generation + AI
```

---

## 🚀 Getting Started

### Requirements
- Godot 4.3+
- No external plugins required

### Running
1. Clone the repository
2. Open `project.godot` in Godot Editor
3. Press F5 or click Play

### Configuration
- **Dungeon parameters**: Adjust in the Inspector on the `DungeonGenerator` node
- **Enemy types**: Create new `AgentConfig` resources in `resources/agent_configs/`
- **AI Director tuning**: Modify exports on the `AIDirector` autoload

---

## 🧪 Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| GDScript over C# | Tighter Godot integration, faster iteration, community standard |
| BSP + CA hybrid | BSP gives structured rooms; CA adds organic variety in transitions |
| Behavior Trees over FSM | More composable, easier to add new behaviors without refactoring |
| Event Bus pattern | Decouples AI, generation, and UI — each system testable in isolation |
| Resource-based configs | Designers can create enemy variants in-editor without code changes |

---

## 🔬 AI Research Applications

This system is designed with AI research extensibility in mind:

- **DungeonData export** — Full grid state serializable to JSON for training data generation
- **Agent telemetry** — EventBus captures all agent decisions, state transitions, and combat events
- **Deterministic replay** — Seed-based generation enables reproducible environments
- **Pluggable BT nodes** — New AI behaviors can be injected via custom `ActionNode` callables
- **Performance metrics** — AI Director's rolling performance window provides ground-truth difficulty labels

---

## 📄 License

MIT License — see [LICENSE](LICENSE)

---

## Quick Start

1. Open `project.godot` in Godot 4.2+
2. Run the main scene -- dungeon generates procedurally each run
3. Set `debug_draw = true` on any AIAgent node to visualize perception cones and paths

---

## Architecture

    AIAgent
    +-- PerceptionComponent  (sight cone + hearing radius)
    +-- SteeringComponent    (seek / arrive / flee forces)
    +-- BehaviorTree         (priority selector root)
    |   +-- Flee sequence    (health < 20%)
    |   +-- Attack sequence  (target in range)
    |   +-- Pursue sequence  (target visible)
    |   +-- Investigate      (heard noise)
    |   +-- Patrol           (default)
    +-- EventBus             (decoupled signals)

---

## Dungeon Generation

The generator uses **Binary Space Partitioning (BSP)**:

1. Recursively split the arena into sub-rectangles until rooms reach min size
2. Place a room inside each leaf with random padding
3. Connect adjacent rooms with L-shaped corridors
4. Build A* navigation graph from walkable tiles
5. Place agents at room centers, respecting faction spawn rules
