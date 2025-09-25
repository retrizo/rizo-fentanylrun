# Inspired Series — **Fentanyl Run** 🚚💊

> **Quick summary:**  
> Script inspired by top-tier server experiences (like NoPixel). The player collects a large batch of drugs and makes a single high-risk delivery using an armored vehicle — simple, tense, and rewarding.

---

## ✨ Overview
This script is part of the *Inspired Series* — small projects recreating mechanics I’ve experienced on large servers to test ideas and learn from their design.  
The goal here is a short but intense mission: gather a large amount of drugs, secure the load, and deliver it in an armored car. You load up a large quantity of drugs (you decide what kind and how much), then you take an armored car. This armored car has a tracking device, and you have to wait for the vehicle's tracker to disappear. The track informs the police of the location of the armored car in blips that update depending on the time you set. Once the tracker disappears, you receive a new delivery location for the product and receive your reward.

---

## 🔗 Dependencies
| Required | Notes |
|---:|---|
| `QBcore` / `Qbox` | Works with either framework |
| `ox_lib` | Used for menus, notifications, helpers |
| `ox_inventory` | Expected inventory system |

> These dependencies cover most modern servers. If you’d like to port it to another framework, feel free — the design is intentionally simple to allow easy adaptation.

---

## ⚙️ Installation (quick)
Follow these steps to set it up:

- ✅ Place the script files in your `resources` folder.
- ✅ Import the SQL table:  
- ✅ Adjust `config.lua` to match your server’s settings (spawn points, values, timers, items).
- ✅ Add the resource to your `server.cfg`:
```cfg
ensure rizo-fentanylrun
```

---

## 🧭 Recommended Structure
```
/resources/
└─ rizo-fentanylrun/
   ├─ fxmanifest.lua
   ├─ server/
   ├─ client/
   ├─ config.lua
   └─ fenrun_xp.sql
```

---

## 📝 Design Notes
- Inspired by the `methrun` on NoPixel 3.0 — focus: simplicity + tension.
- Perfect for servers that want a high-risk/high-reward mission.
- Modular — easy to expand with stages, minigames, or NPC escorts.

---

## 📌 Quick Checklist Before Running
- [ ] `QBcore` / `Qbox` running on the server  
- [ ] `ox_lib` and `ox_inventory` installed and working  
- [ ] `fenrun_xp.sql` imported into database  
- [ ] `config.lua` reviewed and adjusted  
- [ ] `server.cfg` includes `ensure rizo-fentanylrun`
