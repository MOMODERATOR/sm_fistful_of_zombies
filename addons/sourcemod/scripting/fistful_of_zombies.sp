/**
 * vim: set ts=4 :
 * =============================================================================
 * Fistful Of Zombies
 * Zombie survival for Fistful of Frags
 *
 * Copyright 2016 CrimsonTautology
 * =============================================================================
 *
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_EXTENSIONS
#tryinclude <steamworks>

#define PLUGIN_VERSION		"1.0.1"
#define PLUGIN_NAME         "[FoF] Fistful Of Zombies"
#define DEBUG				false

#define MAX_KEY_LENGTH	    128
#define MAX_TABLE   	    128

#define GAME_DESCRIPTION    "Fistful Of Zombies"
#define SOUND_ROUNDSTART    "music/standoff1.mp3"
#define SOUND_HEART         "physics/body/body_medium_impact_soft5.wav"
#define SOUND_NOPE          "player/voice/no_no1.wav"

#define ZOMBIE_TEAM         3   //Desperados
#define HUMAN_TEAM          2   //Vigilantes

new Handle:g_Cvar_Enabled = INVALID_HANDLE;
new Handle:g_Cvar_Config = INVALID_HANDLE;
new Handle:g_Cvar_RoundTime = INVALID_HANDLE;
new Handle:g_Cvar_RespawnTime = INVALID_HANDLE;
new Handle:g_Cvar_Ratio = INVALID_HANDLE;

new Handle:g_Cvar_TeambalanceAllowed = INVALID_HANDLE;
new Handle:g_Cvar_TeamsUnbalanceLimit = INVALID_HANDLE;
new Handle:g_Cvar_Autoteambalance = INVALID_HANDLE;

new Handle:g_GearPrimaryTable = INVALID_HANDLE;
new g_GearPrimaryTotalWeight;

new Handle:g_GearSecondaryTable = INVALID_HANDLE;
new g_GearSecondaryTotalWeight;

new Handle:g_LootTable = INVALID_HANDLE;
new g_LootTotalWeight;

new g_Teamplay = INVALID_ENT_REFERENCE;

new g_RoundStart = 0;

new g_Model_Vigilante;
new g_Model_Desperado;
new g_Model_Bandido;
new g_Model_Ranger;
new g_Model_Ghost;
new g_Model_Skeleton;
new g_Model_Train;


public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = "CrimsonTautology",
	description = "Zombie Survival for Fistful of Frags",
	version = PLUGIN_VERSION,
	url = "https://github.com/CrimsonTautology/sm_fistful_of_zombies"
};

public OnPluginStart()
{
    CreateConVar("foz_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_Cvar_Enabled = CreateConVar(
            "foz_enabled",
            "1",
            "Whether or not Fistful of Zombies is enabled");

    g_Cvar_Config = CreateConVar(
            "foz_config",
            "fistful_of_zombies.txt",
            "Location of the Fistful of Zombies configuration file",
            FCVAR_PLUGIN);

    g_Cvar_RoundTime = CreateConVar(
            "foz_round_time",
            "360",
            "How long surviors have to survive in seconds to win a round in Fistful of Zombies",
            FCVAR_PLUGIN);

    g_Cvar_RespawnTime = CreateConVar(
            "foz_respawn_time",
            "15",
            "How long zombies have to wait before respawning in Fistful of Zombies",
            FCVAR_PLUGIN);

    g_Cvar_Ratio = CreateConVar(
            "foz_ratio",
            "0.75",
            "Percentage of players that start as human.",
            FCVAR_PLUGIN,
            true, 0.01,
            true, 1.0);


    HookEvent("player_activate", Event_PlayerActivate);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);

    RegAdminCmd("sm_zombie", Command_Zombie, ADMFLAG_ROOT, "TEST command");//TODO

    AddCommandListener(Command_JoinTeam, "jointeam");
    AddCommandListener(Command_JoinTeam, "equipmenu");
    AddCommandListener(Command_JoinTeam, "chooseteam");

    g_Cvar_TeambalanceAllowed = FindConVar("fof_sv_teambalance_allowed");
    g_Cvar_TeamsUnbalanceLimit = FindConVar("mp_teams_unbalance_limit");
    g_Cvar_Autoteambalance = FindConVar("mp_autoteambalance");

    SetDefaultConVars();

    AutoExecConfig();
}

public OnClientPostAdminCheck(client)
{
    if(!IsEnabled()) return;

    SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
}
public OnClientDisconnect(client)
{
    if(!IsEnabled()) return;
}

public OnMapStart()
{
    if(!IsEnabled()) return;

    //Load configuration
    decl String:file[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_Config, file, sizeof(file));
    LoadFOZFile(file,
        g_GearPrimaryTable, g_GearPrimaryTotalWeight,
        g_GearSecondaryTable, g_GearSecondaryTotalWeight,
        g_LootTable, g_LootTotalWeight
        );

    //Cache materials
    PrecacheSound(SOUND_ROUNDSTART, true);

    g_Model_Vigilante = PrecacheModel("models/playermodels/player1.mdl");
    g_Model_Desperado = PrecacheModel("models/playermodels/player2.mdl");
    g_Model_Bandido = PrecacheModel("models/playermodels/bandito.mdl");
    g_Model_Ranger = PrecacheModel("models/playermodels/frank.mdl");
    g_Model_Ghost = PrecacheModel("models/npc/ghost.mdl");
    g_Model_Skeleton = PrecacheModel("models/skeleton.mdl");
    g_Model_Train = PrecacheModel("models/props/forest/train.mdl");

    ConvertSpawns();
    ConvertWhiskey(g_LootTable, g_LootTotalWeight);
    g_Teamplay = SpawnZombieTeamplay();

    g_RoundStart = GetTime();

    CreateTimer(1.0, Timer_Repeat, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public OnConfigsExecuted()
{
    if(!IsEnabled()) return;

    SetGameDescription(GAME_DESCRIPTION);
}

public Event_PlayerActivate(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;

    new userid = GetEventInt(event, "userid");
    CreateTimer(0.0, Timer_PlayerSpawnDelay, userid, TIMER_FLAG_NO_MAPCHANGE);
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;

    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);

    //A dead human becomes a zombie
    if(IsHuman(client))
    {
        CreateTimer(1.0, Timer_HumanDeathDelay, userid, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Event_RoundStart(Event:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;

    g_RoundStart = GetTime();

    ConvertWhiskey(g_LootTable, g_LootTotalWeight);
    RemoveCrates();
    RandomizeTeams();
}


public Event_RoundEnd(Event:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return;

    g_RoundStart = GetTime();
}

public Action:Event_PlayerTeam(Event:event, const String:name[], bool:dontBroadcast)
{
    if(!IsEnabled()) return Plugin_Continue;

    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);
    new team   = GetEventInt(event, "team");
    new oldteam   = GetEventInt(event, "oldteam");

    //If A player joins in late as a human force them to be a zombie
    if(team == HUMAN_TEAM && GetTime() - g_RoundStart > 15)
    {
        PrintToServer("-------------blocked %L from joining %d (was %d)", client, team, oldteam);
        CreateTimer(0.1, Timer_HumanDeathDelay, userid, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Handled;
    }

    return Plugin_Continue;

}

public Action:Timer_PlayerSpawnDelay(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);

    if(!IsEnabled()) return Plugin_Handled;
    if(client <= 0) return Plugin_Handled;
    if(!IsClientInGame(client)) return Plugin_Handled;
    if(!IsPlayerAlive(client)) return Plugin_Handled;

    if(IsHuman(client))
    {
        //If a player spawns as human give them their primary and secondary gear
        new String:weapon[MAX_KEY_LENGTH];

        GetRandomValueFromTable(g_GearSecondaryTable, g_GearSecondaryTotalWeight, weapon, sizeof(weapon));
        ForceEquipWeapon(client, weapon, true);

        GetRandomValueFromTable(g_GearPrimaryTable, g_GearPrimaryTotalWeight, weapon, sizeof(weapon));
        ForceEquipWeapon(client, weapon);

        //Force client model
        //SetClientModelIndex(client, g_Model_Vigilante);
        RandomizeModel(client);

        PrintCenterText(client, "Survive the zombie plague!"); 
    } else if(IsZombie(client))
    {
        //Force client model
        SetClientModelIndex(client, g_Model_Skeleton);
        //SetClientModelIndex(client, g_Model_Train);

        PrintCenterText(client, "Ughhhh..... BRAINNNSSSS"); 
    }

    return Plugin_Handled;
}

public Action:Timer_HumanDeathDelay(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);

    if(!IsEnabled()) return Plugin_Handled;
    if(client <= 0) return Plugin_Handled;
    if(!IsClientInGame(client)) return Plugin_Handled;

    JoinZombieTeam(client);
    SetClientModelIndex(client, g_Model_Skeleton);
    //SetClientModelIndex(client, g_Model_Train);

    return Plugin_Handled;
}

public Action:Timer_Repeat(Handle:timer)
{
    if(!IsEnabled()) return Plugin_Continue;

    for (new client=1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client)) continue;
        if(!IsPlayerAlive(client)) continue;

        if(IsZombie(client))
        {
            StripWeapons(client);
        }
    }

    return Plugin_Handled;
}

public Action:Hook_OnWeaponCanUse(client, weapon)
{
    if(!IsEnabled()) return Plugin_Continue;

    //Block zombies from picking up guns
    if (IsZombie(client)) {
        decl String:class[MAX_KEY_LENGTH];
        GetEntityClassname(weapon, class, sizeof(class));

        if (!StrEqual(class, "weapon_fists")) { //TODO have whitelist mechanic
            PrintCenterText(client, "Zombies Can Not Use Guns"); 
            PrintToChat(client, "Zombies Can Not Use Guns"); 

            return Plugin_Handled;
        }
    }

    return Plugin_Continue;
}


public Action:Command_JoinTeam(client, const String:command[], args) 
{ 
    if(!IsEnabled()) return Plugin_Continue;
    if (!IsClientInGame(client)) return Plugin_Continue; 
    if (client == 0) return Plugin_Continue; 

    //Block non-spectators from changing teams
    if (GetClientTeam(client) > 1) 
    { 
        PrintCenterText(client, "Can Not Change Teams Midgame"); 
        PrintToChat(client, "Can Not Change Teams Midgame"); 
        return Plugin_Stop; 
    } 

    return Plugin_Continue;
}  

public Action:Command_Zombie(client, args)
{
    if(!IsEnabled())
    {
        ReplyToCommand(client, "not_enabled");
        return Plugin_Handled;
    }

    //PrintToChat(client, "team = %d", GetClientTeam(client));
    new Float:speed = GetEntPropFloat(client, Prop_Data, "m_flMaxspeed");
    PrintToChat(client, "speed = %f", speed);

    return Plugin_Handled;
}

LoadFOZFile(String:file[],
        &Handle:gear_primary_table, &gear_primary_total_weight,
        &Handle:gear_secondary_table, &gear_secondary_total_weight,
        &Handle:loot_table, &loot_total_weight)
{
    decl String:path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/%s", file);

    new Handle:config = CreateKeyValues("fistful_of_zombies");
    if(!FileToKeyValues(config, path))
    {
        LogError("Could not read map rotation file \"%s\"", file);
        SetFailState("Could not read map rotation file \"%s\"", file);
        return;
    }

    //Read the default "loot" key and build the loot table
    BuildWeightTable(config, "loot", loot_table, loot_total_weight);
    BuildWeightTable(config, "gear_primary", gear_primary_table, gear_primary_total_weight);
    BuildWeightTable(config, "gear_secondary", gear_secondary_table, gear_secondary_total_weight);

    CloseHandle(config);
}

//Build a table for randomly selecting a weighted value
BuildWeightTable(Handle:kv, const String:name[], &Handle:table, &total_weight)
{
    decl String:key[MAX_KEY_LENGTH];
    new weight;

    if(table != INVALID_HANDLE) CloseHandle(table);
    total_weight = 0;

    KvRewind(kv);

    if(KvJumpToKey(kv, name))
    {
        table = CreateKeyValues(name);
        KvCopySubkeys(kv, table);

        KvGotoFirstSubKey(kv);
        do
        {
            KvGetSectionName(kv, key, sizeof(key));
            weight = KvGetNum(kv, "weight", 0);


            //Ignore values that do not have a weight or 0 weight
            if(weight > 0)
            {
                total_weight += weight;

                PrintToServer( "Add[%s]: %s (%d) (%d)", name, key, weight, total_weight);
            }
        }
        while(KvGotoNextKey(kv));

    }else{
        LogError("A valid \"%s\" key was not defined", name);
        SetFailState("A valid \"%s\" key was not defined", name);
    }

    KvRewind(kv);
}

SetDefaultConVars()
{
    SetConVarBool(g_Cvar_TeambalanceAllowed, false, false, false);
    SetConVarInt(g_Cvar_TeamsUnbalanceLimit, 30, false, false);
    SetConVarBool(g_Cvar_Autoteambalance, false, false, false);
}

RemoveCrates()
{
    new ent = INVALID_ENT_REFERENCE;
    while((ent = FindEntityByClassname(ent, "fof_crate*")) != INVALID_ENT_REFERENCE)
    {
        AcceptEntityInput(ent, "Kill" );
    }
}

RemoveWeapons()
{
    new ent = INVALID_ENT_REFERENCE;
    while((ent = FindEntityByClassname(ent, "weapon*")) != INVALID_ENT_REFERENCE)
    {
        AcceptEntityInput(ent, "Kill" );
    }
    while((ent = FindEntityByClassname(ent, "dynamite*")) != INVALID_ENT_REFERENCE)
    {
        AcceptEntityInput(ent, "Kill" );
    }
}

//Change all info_player_fof spawn points to a round robin
//info_player_desperado and info_player_vigilante.
ConvertSpawns()
{
    new count = 0;
    new original  = INVALID_ENT_REFERENCE;
    new converted = INVALID_ENT_REFERENCE;
    new Float:pos[3], Float:ang[3];

    while((original = FindEntityByClassname(original, "info_player_fof")) != INVALID_ENT_REFERENCE)
    {
        //Get original's position and remove it
        GetEntPropVector(original, Prop_Send, "m_vecOrigin", pos);
        GetEntPropVector(original, Prop_Send, "m_angRotation", ang);
        AcceptEntityInput(original, "Kill" );

        //Spawn a replacement at the same position
        converted = count % 2 == 0
            ? CreateEntityByName("info_player_vigilante")
            : CreateEntityByName("info_player_desperado")
            ;
        if(IsValidEntity(converted))
        {
            DispatchKeyValueVector(converted, "origin", pos);
            DispatchKeyValueVector(converted, "angles", ang);
            DispatchKeyValue(converted, "StartDisabled", "0");
            DispatchSpawn(converted);
            ActivateEntity(converted);
        }

        count++;
    }

}

//Whiskey is used as the spawn points for the random loot accross the map.
//Every whiskey entity is removed and replaced with a random item/weapon.
ConvertWhiskey(Handle:loot_table, loot_total_weight)
{
    decl String:loot[MAX_KEY_LENGTH];
    new count = 0;
    new original  = INVALID_ENT_REFERENCE;
    new converted = INVALID_ENT_REFERENCE;
    new Float:pos[3], Float:ang[3];

    while((original = FindEntityByClassname(original, "item_whiskey")) != INVALID_ENT_REFERENCE)
    {
        //Get original's position and remove it
        GetEntPropVector(original, Prop_Send, "m_vecOrigin", pos);
        GetEntPropVector(original, Prop_Send, "m_angRotation", ang);
        AcceptEntityInput(original, "Kill" );

        //Spawn a replacement at the same position
        GetRandomValueFromTable(loot_table, loot_total_weight, loot, sizeof(loot));
        if(StrEqual(loot, "nothing", false)) continue;

        converted = CreateEntityByName(loot);//TODO
        PrintToServer("Whiskey[%d] to %s", count, loot);//TODO
        if(IsValidEntity(converted))
        {
            DispatchKeyValueVector(converted, "origin", pos);
            DispatchKeyValueVector(converted, "angles", ang);
            DispatchSpawn(converted);
            ActivateEntity(converted);
        }

        count++;
    }
}

//Spawn the fof_teamplay entity that will control the game's logic.
SpawnZombieTeamplay()
{
    new String:tmp[512];


    new ent = CreateEntityByName("fof_teamplay");
    if(IsValidEntity(ent))
    {
        DispatchKeyValue(ent, "targetname", "tpzombie");

        DispatchKeyValue(ent, "RoundBased", "1");
        DispatchKeyValue(ent, "RespawnSystem", "1");
        DispatchKeyValue(ent, "SwitchTeams", "1");

        //Todo, cvar ExtraTime and RoundTime
        Format(tmp, sizeof(tmp),                 "!self,RoundTime,%d,0,-1", GetRoundTime());
        DispatchKeyValue(ent, "OnNewRound",      tmp);
        DispatchKeyValue(ent, "OnNewRound",      "!self,ExtraTime,15,0.1,-1");

        Format(tmp, sizeof(tmp),                 "!self,ExtraTime,%d,0,-1", GetRespawnTime());
        DispatchKeyValue(ent, "OnTimerEnd",      tmp);
        DispatchKeyValue(ent, "OnTimerEnd",      "!self,InputRespawnPlayers,-2,0,-1");

        DispatchKeyValue(ent, "OnRoundTimeEnd",  "!self,InputVigVictory,,0,-1");
        DispatchKeyValue(ent, "OnNoDespAlive",   "!self,InputRespawnPlayers,-2,0,-1");
        DispatchKeyValue(ent, "OnNoVigAlive",    "!self,InputDespVictory,,0,-1");

        DispatchSpawn(ent);
        ActivateEntity(ent);

        //OnRoundTimeEnd //Winner is Humans(vig)
        //OnNoDespAlive  //Respawn Zombies(desp)
        //OnNoVigAlive   //Winner is Zombies(desp)
        //OnNewBuyRound  //Block or remove cash
    }

    return ent;
}

stock bool:IsEnabled()
{
    return GetConVarBool(g_Cvar_Enabled);
}

stock bool:IsHuman(client)
{
    return GetClientTeam(client) == HUMAN_TEAM;
}

stock bool:IsZombie(client)
{
    return GetClientTeam(client) == ZOMBIE_TEAM;
}

stock JoinHumanTeam(client)
{
    ChangeClientTeam(client, HUMAN_TEAM);
}

stock JoinZombieTeam(client)
{
    ChangeClientTeam(client, ZOMBIE_TEAM);
}

stock RandomizeTeams()
{
  decl clients[MAXPLAYERS];
  new client_count = 0, human_count;
  new Float:ratio = GetConVarFloat(g_Cvar_Ratio);

  for(new client = 1; client <= MaxClients; client++)
  {
      if(!IsClientInGame(client)) continue;
      if(!( IsZombie(client) || IsHuman(client) )) continue;

      client_count++;
      clients[client_count] = client;
  }

  SortIntegers(clients, client_count, Sort_Random);

  //Calculate number of humans;  need at least one
  human_count = RoundToFloor(client_count * ratio);
  if(human_count == 0 && client_count > 0) human_count = 1;

  //Assign teams
  for(new i = 0; i < human_count; i++)
  {
      JoinHumanTeam(clients[i]);
  }
  for(new i = human_count; i < client_count; i++)
  {
      JoinZombieTeam(clients[i]);
  }
}

stock GetRoundTime()
{
    return GetConVarInt(g_Cvar_RoundTime);
}

stock GetRespawnTime()
{
    return GetConVarInt(g_Cvar_RespawnTime);
}

stock bool:GetRandomValueFromTable(Handle:table, total_weight, String:value[], length)
{
    new weight;
    new rand = GetRandomInt(0, total_weight - 1);

    KvRewind(table);
    KvGotoFirstSubKey(table);
    do
    {
        KvGetSectionName(table, value, length);
        weight = KvGetNum(table, "weight", 0);
        if(weight <= 0) continue;

        if(rand < weight){
            KvRewind(table);
            return true;
        }
        rand -= weight;
    }
    while(KvGotoNextKey(table));
    KvRewind(table);

    return false;
}

stock ForceEquipWeapon(client, const String:weapon[], bool second=false)
{
    new String:tmp[MAX_KEY_LENGTH];

    GivePlayerItem(client, weapon);

    PrintToChat(client, "Given %s", weapon);

    Format(tmp, sizeof(tmp), "use %s%s", weapon, second ? "2" : "");
    ClientCommand(client, tmp);
}

stock RandomizeModel(client)
{
    new model;

    if(IsZombie(client))
    {
        model = GetRandomInt(0, 3);
        switch (model)
        {
            case 0: { SetClientModelIndex(client, g_Model_Vigilante); }
            case 1: { SetClientModelIndex(client, g_Model_Desperado); }
            case 2: { SetClientModelIndex(client, g_Model_Bandido); }
            case 3: { SetClientModelIndex(client, g_Model_Ranger); }
        }

    } else if(IsZombie(client))
    {
        model = GetRandomInt(0, 1);
        switch (model)
        {
            case 0: { SetClientModelIndex(client, g_Model_Ghost); }
            case 1: { SetClientModelIndex(client, g_Model_Skeleton); }
        }
    }
}

StripWeapons(client)
{
    new weapon_ent;
    decl String:class_name[MAX_KEY_LENGTH];
    new offs = FindSendPropInfo("CBasePlayer","m_hMyWeapons");

    for(new i = 0; i <= 47; i++)
    {
        weapon_ent = GetEntDataEnt2(client,offs + (i * 4));
        if(weapon_ent == -1) continue;

        GetEdictClassname(weapon_ent, class_name, sizeof(class_name));
        if(StrEqual(class_name, "weapon_fists")) continue;

        RemovePlayerItem(client, weapon_ent);
        RemoveEdict(weapon_ent);
    }

}

stock bool SetClientModelIndex(client, index)
{
    SetEntProp(client, Prop_Data, "m_nModelIndex", index, 2);
}

stock bool:SetGameDescription(String:description[], bool:override = true)
{
#if defined _SteamWorks_Included
    if(override) return SteamWorks_SetGameDescription(description);
#endif
    return false;
}

stock WriteLog(const String:format[], any:... )
{
#if defined DEBUG
    if(format[0] != '\0')
    {
        decl String:buf[2048];
        VFormat(buf, sizeof(buf), format, 2 );
        //LogToFileEx("log_zombie.txt", "[%.3f] %s", GetGameTime(), buf);
        PrintToServer("[%.3f] %s", GetGameTime(), buf);
    }
#endif
}
