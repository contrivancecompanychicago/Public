#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#include <ttt>
#include <ttt_shop>

#include <config_loader>

#pragma newdecls required

#define PLUGIN_NAME TTT_PLUGIN_NAME ... " - Knockout"
#define SHORT_NAME "knockout"

int g_iPrice = -1;
int g_iPrio = -1;

int g_iCollisionGroup = -1;
int g_iFreeze = -1;
int g_iMyWeapons = -1;

int g_iRagdoll[MAXPLAYERS + 1] =  { -1, ... };
int g_iCamera[MAXPLAYERS + 1] =  { -1, ... };

bool g_bHasKnockout[MAXPLAYERS + 1] =  { false, ... };
bool g_bKnockout[MAXPLAYERS + 1] =  { false, ... };

char g_sConfigFile[PLATFORM_MAX_PATH] = "";
char g_sPluginTag[PLATFORM_MAX_PATH] = "";
char g_sLongName[64];

UserMsg g_uFade = view_as<UserMsg>(-1);

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = TTT_PLUGIN_AUTHOR,
	description = TTT_PLUGIN_DESCRIPTION,
	version = TTT_PLUGIN_VERSION,
	url = TTT_PLUGIN_URL
};

public void OnPluginStart()
{
	TTT_IsGameCSGO();
	
	g_iCollisionGroup = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	if (g_iCollisionGroup == -1)
	{
		SetFailState("m_CollisionGroup not found...");
	}
	
	g_iFreeze = FindSendPropInfo("CBasePlayer", "m_fFlags");
	if (g_iFreeze == -1)
	{
		SetFailState("m_fFlags not found...");
	}
	
	g_iMyWeapons = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");
	if (g_iMyWeapons == -1)
	{
		SetFailState("m_hMyWeapons not found...");
	}
	
	g_uFade = GetUserMessageId("Fade");
	if (g_uFade == view_as<UserMsg>(-1))
	{
		SetFailState("Failure with UserMessage Fade...");
	}
	
	LoadTranslations("ttt.phrases");
	
	BuildPath(Path_SM, g_sConfigFile, sizeof(g_sConfigFile), "configs/ttt/config.cfg");
	Config_Setup("TTT", g_sConfigFile);
	
	Config_LoadString("ttt_plugin_tag", "{orchid}[{green}T{darkred}T{blue}T{orchid}]{lightgreen} %T", "The prefix used in all plugin messages (DO NOT DELETE '%T')", g_sPluginTag, sizeof(g_sPluginTag));
	
	Config_Done();

	BuildPath(Path_SM, g_sConfigFile, sizeof(g_sConfigFile), "configs/ttt/knockout.cfg");
	Config_Setup("TTT-Knockout", g_sConfigFile);
	
	Config_LoadString("knockout_name", "Knockout", "The name of this in Shop", g_sLongName, sizeof(g_sLongName));
	g_iPrice = Config_LoadInt("knockout_price", 9000, "The amount of credits a knockout costs as detective. 0 to disable.");
	g_iPrio = Config_LoadInt("knockout_sort_prio", 0, "The sorting priority of the knockout in the shop menu.");
	
	Config_Done();
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	LoopValidClients(i)
	{
		OnClientPutInServer(i);
	}
}

public void OnAllPluginsLoaded()
{
	TTT_RegisterCustomItem(SHORT_NAME, g_sLongName, g_iPrice, TTT_TEAM_TRAITOR, g_iPrio);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
}

public void OnClientDisconnect(int client)
{
	ResetKnockout(client);
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (TTT_IsClientValid(client))
	{
		ResetKnockout(client);
	}
}

public Action TTT_OnItemPurchased(int client, const char[] itemshort, bool count)
{
	if (TTT_IsClientValid(client) && IsPlayerAlive(client))
	{
		if (StrEqual(itemshort, SHORT_NAME, false))
		{
			int role = TTT_GetClientRole(client);
			
			if (role != TTT_TEAM_TRAITOR)
			{
				return Plugin_Stop;
			}
			
			g_bHasKnockout[client] = true;
			
			for(int offset = 0; offset < 128; offset += 4)
			{
				int weapon = GetEntDataEnt2(client, g_iMyWeapons + offset);
				
				if (IsValidEntity(weapon))
				{
					char sClass[32];
					GetEntityClassname(weapon, sClass, sizeof(sClass));
					
					if (StrEqual(sClass, "weapon_taser", false))
					{
						TTT_SafeRemoveWeapon(client, weapon);
					}
				}
			}
			GivePlayerItem(client, "weapon_taser");
		}
	}
	return Plugin_Continue;
}

public Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	if (!TTT_IsRoundActive())
	{
		return Plugin_Continue;
	}
	
	if (TTT_IsClientValid(attacker))
	{
		if (g_bHasKnockout[attacker])
		{
			char sWeapon[32];
			GetClientWeapon(attacker, sWeapon, sizeof(sWeapon));
			
			if (StrContains(sWeapon, "taser", false) != -1)
			{
				KnockoutPlayer(victim);
				g_bHasKnockout[attacker] = false;
				
				damage = 0.0;
				return Plugin_Changed;
			}
		}
	}
	
	return Plugin_Continue;
}

void KnockoutPlayer(int client)
{
	g_bKnockout[client] = true;

	char sModel[256];
	GetClientModel(client, sModel, sizeof(sModel));

	float pos[3];
	GetClientEyePosition(client, pos);

	int iEntity = CreateEntityByName("prop_ragdoll");
	DispatchKeyValue(iEntity, "model", sModel);
	DispatchKeyValue(iEntity, "targetname", "fake_body");
	SetEntProp(iEntity, Prop_Data, "m_nSolidType", 6);
	SetEntProp(iEntity, Prop_Data, "m_CollisionGroup", 5);
	DispatchSpawn(iEntity);

	pos[2] -= 16.0;
	TeleportEntity(iEntity, pos, NULL_VECTOR, NULL_VECTOR);
	SetNoblock(iEntity);

	g_iRagdoll[client] = iEntity;
	SetNoblock(client);
	SetEntityRenderMode(client, RENDER_NONE);
	DropAllWeapons(client);
	SetNonMoveable(client);

	CreateTimer(5.0, Timer_Delete, client, TIMER_FLAG_NO_MAPCHANGE);

	SpawnCamAndAttach(client, iEntity);

	PerformBlind(client, 255);
}

public Action Timer_Delete(Handle timer, any client)
{
	int entity = g_iRagdoll[client];

	if (entity != -1 && IsValidEntity(entity))
		AcceptEntityInput(entity, "kill");

	g_iRagdoll[client] = -1;
	g_bKnockout[client] = false;

	if(IsClientInGame(client) && IsPlayerAlive(client))
	{
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetBlock(client);
		SetMoveable(client);
		SetClientViewEntity(client, client);
		g_iCamera[client] = false;
		PerformBlind(client, 0);
	}
}

void ResetKnockout(int client)
{
	g_bHasKnockout[client] = false;
}

void SetNoblock(int entity)
{
	SetEntData(entity, g_iCollisionGroup, 2, 4, true);
}

void SetBlock(int entity)
{
	SetEntData(entity, g_iCollisionGroup, 5, 4, true);
}

void SetMoveable(int entity)
{
	SetEntData(entity, g_iFreeze, FL_CLIENT|FL_ATCONTROLS, 4, true);
}

void SetNonMoveable(int entity)
{
	SetEntData(entity, g_iFreeze, FL_FAKECLIENT|FL_ONGROUND|FL_PARTIALGROUND, 4, true);
}


void DropAllWeapons(int client)
{
	for (int i = CS_SLOT_PRIMARY; i <= CS_SLOT_C4; i++)
	{
		int weapon = -1;
		while ((weapon = GetPlayerWeaponSlot(client, i)) != -1)
		{
			SDKHooks_DropWeapon(client, weapon);
		}
	}
}

stock bool SpawnCamAndAttach(int client, int ragdoll)
{
	char sModel[64];
	Format(sModel, sizeof(sModel), "models/blackout.mdl");
	PrecacheModel(sModel, true);

	char sModelName[64];
	Format(sModelName, sizeof(sModelName), "fpd_ragdoll%d", client);
	DispatchKeyValue(ragdoll, "targetname", sModelName);

	int entity = CreateEntityByName("prop_dynamic");
	if (entity == -1)
	{
		return false;
	}

	char sEntityName[64];
	Format(sEntityName, sizeof(sEntityName), "fpd_ragdollCam%d", entity);

	DispatchKeyValue(entity, "targetname", sEntityName);
	DispatchKeyValue(entity, "parentname", sModelName);
	DispatchKeyValue(entity, "model",	  sModel);
	DispatchKeyValue(entity, "solid",	  "0");
	DispatchKeyValue(entity, "rendermode", "10");
	DispatchKeyValue(entity, "disableshadows", "1");

	float angles[3]; GetClientEyeAngles(client, angles);
	char CamTargetAngles[64];
	Format(CamTargetAngles, 64, "%f %f %f", angles[0], angles[1], angles[2]);
	DispatchKeyValue(entity, "angles", CamTargetAngles);

	SetEntityModel(entity, sModel);
	DispatchSpawn(entity);

	SetVariantString(sModelName);
	AcceptEntityInput(entity, "SetParent", entity, entity, 0);

	SetVariantString("forward");
	AcceptEntityInput(entity, "SetParentAttachment", entity, entity, 0);

	AcceptEntityInput(entity, "TurnOn");

	SetClientViewEntity(client, entity);
	g_iCamera[client] = entity;

	return true;
}

void PerformBlind(int client, int amount)
{
	int targets[2];
	targets[0] = client;

	int duration = 1536;
	int holdtime = 1536;
	int flags;
	if (amount == 0)
		flags = (0x0001 | 0x0010);
	else flags = (0x0002 | 0x0008);

	int color[4] = { 0, 0, 0, 0 };
	color[3] = amount;

	Handle message = StartMessageEx(g_uFade, targets, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		PbSetInt(message, "duration", duration);
		PbSetInt(message, "hold_time", holdtime);
		PbSetInt(message, "flags", flags);
		PbSetColor(message, "clr", color);
	}
	else
	{
		BfWriteShort(message, duration);
		BfWriteShort(message, holdtime);
		BfWriteShort(message, flags);
		BfWriteByte(message, color[0]);
		BfWriteByte(message, color[1]);
		BfWriteByte(message, color[2]);
		BfWriteByte(message, color[3]);
	}

	EndMessage();
}