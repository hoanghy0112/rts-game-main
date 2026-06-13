# 11 - Nguồn tham khảo và kiểm chứng

## Engine/framework sources checked

Checked on 2026-06-07.

- Godot 4.5 release page: https://godotengine.org/releases/4.5/
- Godot documentation: introduction/license/open-source overview: https://docs.godotengine.org/en/stable/about/introduction.html
- Godot documentation: GDScript section: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/index.html
- Bevy official site: https://bevy.org/
- Bevy 0.18 release/news if using Bevy comparison: https://bevy.org/news/
- Unity pricing/licensing page: https://unity.com/products/pricing-updates
- Unity Hub documentation: https://docs.unity.com/en-us/hub
- Unreal Engine Linux development requirements: https://dev.epicgames.com/documentation/en-us/unreal-engine/linux-development-requirements-for-unreal-engine

## Geography/data sources to evaluate after v0

V0 does not import a Vietnam map. These sources are candidates for a future adapter that converts real geography into the neutral map pack format.

- NASA SRTM elevation data: https://www.earthdata.nasa.gov/data/instruments/srtm
- HydroSHEDS hydrographic data: https://www.hydrosheds.org/
- Natural Earth public-domain GIS data: https://www.naturalearthdata.com/
- OpenStreetMap data and license: https://www.openstreetmap.org/copyright
- GADM administrative boundaries and license: https://gadm.org/license.html

Use modern geography sources as physical proxies only after the adapter phase. They do not prove 15th-century historical roads, forts, settlements or resource yields.

Generated v0 maps must be labeled as fictional/procedural content and must not carry historical source claims.

## Historical validation workflow

Every historical entry must have:

```json
{
  "source_id": "source_001",
  "title": "Full title",
  "author": "Author/editor",
  "publisher": "Publisher/institution",
  "year": "YYYY",
  "type": "primary|secondary|academic|museum|encyclopedia|map|uncertain",
  "url_or_citation": "URL or bibliographic citation",
  "accessed": "YYYY-MM-DD",
  "confidence": "low|medium|high",
  "notes": "What this source supports"
}
```

Historical object rule:

```text
strict campaign object is valid only if:
    source_ids.count >= 1
    confidence != "low" OR object is marked uncertain
```

## Content confidence levels

| Level | Meaning | UI/content use |
|---|---|---|
| high | supported by strong source or multiple independent sources | campaign-safe |
| medium | plausible and sourced, but exact position/value uncertain | campaign-safe with note |
| low | weakly sourced or inferred | not used in strict campaign as fact |
| fictional | gameplay invention | random/alternate only |

## Historical campaign source policy

The campaign content should be source-backed. Do not add exact battle details, army sizes, routes or resource yields without source registration.

Recommended source categories:

- Regional historical chronicles/translations;
- academic histories of the target period;
- peer-reviewed articles;
- museum/archival material;
- historical atlases;
- archaeological/geographical studies.

## Scenario validation rules

Validator fails if:

- scenario `historical_accuracy = requires_source` and any historical object lacks `source_ids`;
- object period falls outside scenario period;
- faction has unit enabled that scenario explicitly disallows;
- source confidence is `low` but object is not marked uncertain;
- resource yield claims exact historical output without source;
- map marker uses modern administrative name as 15th-century fact without note.

Validator warns if:

- modern geography proxy is used without historical override;
- source is encyclopedia-only for important campaign event;
- object position has confidence radius > configured threshold;
- unit/equipment may be anachronistic.

## How to store uncertainty

For positions:

```json
{
  "position_m": { "x": 1000, "y": 2000 },
  "confidence_radius_m": 5000,
  "confidence": "medium"
}
```

For quantities:

```json
{
  "army_size_estimate": {
    "min": 1000,
    "max": 3000,
    "confidence": "low",
    "source_ids": ["source_010"]
  }
}
```

For gameplay interpolation:

```json
{
  "historical": false,
  "design_note": "Created to teach supply route mechanics."
}
```

## Data audit checklist

Before campaign content ships:

- all strict historical objects have source IDs;
- all uncertain positions have radius;
- anachronistic equipment is disabled or labeled alternate;
- modern roads/regions are not presented as 15th-century facts;
- every event has source or `historical: false`;
- all formulas used by scenario are in config and testable;
- no magic numbers hidden in event scripts.
