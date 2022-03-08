/******************** [ ChangeLog ] ******************** 

	1.0 - Pierwsze wydanie pluginu.
	1.1 - Dodanie możliwości zmiany wyglądu rang w tabeli.
	1.2 - Optymalizacja kodu, poprawienie komunikatów na chacie pod względem estetycznym, zmiana timera zapisującego dane na akcję w Event_RoundEnd
	1.3 - Dodanie opcji wyłączenia złotych naboi, zmiana kominkatów, ukrywanie opcji przy wyłączonych złotych nabojach.
	1.4 - Dodanie hudu
	1.5 - Poprawiono błąd związany z hudem.
	1.6 - Dodano Convar decydujący o tym czy hud ma być aktywny, dodano punkty za asystę
	2.0 - Przepisanie kodu na nowo.
	2.1 - Naprawienie kilku błędów, dodano kompatybilność pod SCP.
	2.2 - Optymalizacja kodu, poprawa istniejących błędów, dodano nowy rodzaj topki, rozszerzono stare funckje.
	2.3 - Dodano Nativy 
	
******************** [ ChangeLog ] ********************/

/* [ Includes ] */
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <pRanks-Core>
#include <cstrike>
#include <multicolors>
#include <chat-processor>

/* [ Compiler Options ] */
#pragma newdecls required
#pragma semicolon 1

/* [ Defines ] */
#define LoopClients(%1)			for(int %1 = 1; %1 < MaxClients; %1++) if(IsValidClient(%1))
#define PluginTag_Info			"★ {lightred}[ Rangi ]{default}"
#define Table_Main				"pRanks_Main"
#define Table_Stats				"pRanks_Stats"
#define RankUp					"pawel_ranks/rank_up.mp3"
#define RankDown				"pawel_ranks/rank_down.mp3"

/* [ Database ] */
Database g_dbDatabase;

/* [ Handles ] */
Handle g_hRankUp, g_hRankDown;

/* [ Array Lists ] */
ArrayList g_arRanks[5];

/* [ Handles ] */
Handle g_hHud;

/* [ Integers ] */
int g_iCvar[21];
int g_iHud[MAXPLAYERS + 1];
int g_iPoints[MAXPLAYERS + 1];
int g_iStats[MAXPLAYERS + 1][7];
int g_iRank[MAXPLAYERS + 1];
int g_iTarget[MAXPLAYERS + 1];
int g_iTime[MAXPLAYERS + 1];
int g_iOverlay[MAXPLAYERS + 1];

/* [ Chars ] */
char g_sLogFile[PLATFORM_MAX_PATH];

/* [ Booleans ] */
bool g_bIsDataLoaded[MAXPLAYERS + 1][2];
bool g_bPoints[MAXPLAYERS + 1][2];

/* [ Plugin Author And Informations ] */
public Plugin myinfo =  {
	name = "[CS:GO] Pawel - [ pRanks ]", 
	author = "Pawel", 
	description = "System rankingowy na serwery CS:GO by Pawel.", 
	version = "2.3", 
	url = "https://steamcommunity.com/id/pawelsteam"
};

/* [ Plugin Startup ] */
public void OnPluginStart() {
	/* [ Commands ] */
	RegConsoleCmd("sm_ap", AdminPanel_Command, "Panel administracyjny");
	RegConsoleCmd("sm_ranks", Ranks_Command, "Główne menu");
	RegConsoleCmd("sm_ranga", Ranks_Command, "Główne menu");
	RegConsoleCmd("sm_rangi", Ranks_Command, "Główne menu");
	RegConsoleCmd("sm_rank", Ranks_Command, "Główne menu");
	RegConsoleCmd("sm_hud", Hud_Command, "Wybór hudu");
	RegConsoleCmd("say", Say_Command);
	RegConsoleCmd("say_team", Say_Command);
	
	/* [ Hooks ] */
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("bomb_defused", Event_BombDefused);
	HookEvent("bomb_planted", Event_BombPlanted);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("hostage_rescued", Event_HostageRescued);
	
	/* [ Timers ] */
	CreateTimer(360.0, Timer_AuthorInfo, _, TIMER_FLAG_NO_MAPCHANGE);
	
	/* [ Database Connect ] */
	Database.Connect(SQL_Connect_Handler, "Pawel_Ranks");
	
	/* [ Array Lists ] */
	ArraysAction(0);
	
	/* [ Forwards ] */
	g_hRankUp = CreateGlobalForward("pRanks_RankUp", ET_Ignore, Param_Cell, Param_Cell);
	g_hRankDown = CreateGlobalForward("pRanks_RankDown", ET_Ignore, Param_Cell, Param_Cell);
	
	/* [ Hud ] */
	g_hHud = CreateHudSynchronizer();
	
	/* [ Check Players ] */
	LoopClients(i)
	OnClientPutInServer(i);
	
	/* [ LogFile ] */
	char sDate[16];
	FormatTime(sDate, sizeof(sDate), "%Y-%m-%d", GetTime());
	BuildPath(Path_SM, g_sLogFile, sizeof(g_sLogFile), "logs/Rangi/%s.log", sDate);
}

/* [ Standard Actions ] */
public void OnConfigsExecuted() {
	if (g_dbDatabase == null)
		Database.Connect(SQL_Connect_Handler, "Pawel_Ranks");
}

public void OnMapStart() {
	LoadConfig();
	char sBuffer[128];
	for (int i = 1; i < 19; i++) {
		Format(sBuffer, sizeof(sBuffer), "materials/panorama/images/icons/skillgroups/skillgroup%d.svg", 50 + i);
		AddFileToDownloadsTable(sBuffer);
		Format(sBuffer, sizeof(sBuffer), "pawel_ranks/rank_%d", i);
		PrecacheDecalAnyDownload(sBuffer);
	}
	for (int i = 1; i < 16; i++) {
		Format(sBuffer, sizeof(sBuffer), "materials/panorama/images/icons/skillgroups/skillgroup%d.svg", 70 + i);
		AddFileToDownloadsTable(sBuffer);
	}
	PrecacheSoundAnyDownload(RankUp);
	PrecacheSoundAnyDownload(RankDown);
	SDKHook(FindEntityByClassname(MaxClients + 1, "cs_player_manager"), SDKHook_ThinkPost, OnThinkPost);
	CreateTimer(0.5, Timer_UpdateStatus, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(60.0, Timer_AddMinute, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int client) {
	Reset(client);
	SQL_PrepareLoadData(client);
}

public void OnClientDisconnect(int client) {
	if (IsValidClient(client)) {
		char sAuthId[64], sRank[64];
		g_arRanks[1].GetString(g_iRank[client], sRank, sizeof(sRank));
		GetClientAuthId(client, AuthId_Steam2, sAuthId, sizeof(sAuthId));
		LogToFileEx(g_sLogFile, "[ Rangi -> Main ] [ Wyjście ]	| %N (%s) przy wyjściu posiadał: rangę %s (%d), %d punktów, %d minut", client, sAuthId, sRank, g_iRank[client], g_iPoints[client], g_iTime[client]);
		LogToFileEx(g_sLogFile, "[ Rangi -> Stats ] [ Wyjście ]	| %N (%s) przy wyjściu posiadał: %d zabójstw, %d headshotów, %d assyst, %d śmierci, %d podłożonych bomb, %d rozbrojonych bomb, %d uratowanych zakładników.", client, sAuthId, g_iStats[client][0], g_iStats[client][1], g_iStats[client][2], g_iStats[client][3], g_iStats[client][4], g_iStats[client][5], g_iStats[client][6]);
	}
}

public void OnMapEnd() {
	LoopClients(i)
	OnClientDisconnect(i);
	SDKUnhook(FindEntityByClassname(MaxClients + 1, "cs_player_manager"), SDKHook_ThinkPost, OnThinkPost);
	ArraysAction(1);
}

public void OnPluginEnd() {
	LoopClients(i)
	OnClientDisconnect(i);
}

/* [ Commands ] */
public Action Ranks_Command(int client, int args) {
	char sBuffer[256], sRank[64];
	g_arRanks[1].GetString(g_iRank[client], sRank, sizeof(sRank));
	Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Menu Główne ★ ]\n ");
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Ranga: %s\n ", sBuffer, sRank);
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Punkty: %d pkt.", sBuffer, g_iPoints[client]);
	if (g_iRank[client] < g_arRanks[0].Length - 1) {
		int points = g_arRanks[2].Get(g_iRank[client] + 1) - g_iPoints[client];
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Awans otrzymasz za %d pkt.\n ", sBuffer, points);
	}
	else
		Format(sBuffer, sizeof(sBuffer), "%s\n ", sBuffer);
	
	Menu menu = new Menu(Ranks_Handler);
	menu.SetTitle(sBuffer);
	menu.AddItem("", "» Panel Gracza");
	menu.AddItem("", "» Ranking");
	menu.AddItem("", "» Topka czasu");
	menu.AddItem("", "» Topka rang");
	menu.AddItem("", "» Zarządzanie Hudem\n ");
	if (HasAcces(client))
		menu.AddItem("", "» Panel Administratora\n ");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Ranks_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			switch (position) {
				case 0:Player_Panel(client);
				case 1:ShowRank(client, 0);
				case 2:ShowRank(client, 1);
				case 3:ShowRank(client, 2);
				case 4:Hud_Command(client, 0);
				case 5:AdminPanel_Command(client, 0);
			}
		}
		case MenuAction_End:delete menu;
	}
}

void Player_Panel(int client) {
	char sBuffer[256];
	Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Menu Gracza ★ ]\n ");
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj, %N!", sBuffer, client);
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Wybierz interesującą Cię pozycję z menu.\n ", sBuffer);
	Menu menu = new Menu(Player_Handler);
	menu.SetTitle(sBuffer);
	menu.AddItem("", "» Spis rang oraz wymagania.");
	menu.AddItem("", "» Punktacja za eventy.");
	menu.AddItem("", "» Statystyki konta.");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Player_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			char sBuffer[512], sRank[64];
			switch (position) {
				case 0: {
					Menu menu2 = new Menu(List_Handler);
					menu2.SetTitle("[ ★ Rangi » Spis Rang ★ ]\n ");
					for (int i = 0; i < g_arRanks[0].Length; i++) {
						g_arRanks[1].GetString(i, sRank, sizeof(sRank));
						Format(sBuffer, sizeof(sBuffer), "» %s ➪ %d pkt.", sRank, g_arRanks[2].Get(i));
						menu2.AddItem("", sBuffer, ITEMDRAW_DISABLED);
					}
					if (menu2.ItemCount == 0)
						menu2.AddItem("", "» Brak rang na serwerze.", ITEMDRAW_DISABLED);
					menu2.ExitBackButton = true;
					menu2.Display(client, MENU_TIME_FOREVER);
				}
				case 1:Points(client, 0);
				case 2: {
					char sTime[64];
					FormatTimes(g_iTime[client], sTime, sizeof(sTime));
					g_arRanks[1].GetString(g_iRank[client], sRank, sizeof(sRank));
					Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Statystyki Konta ★ ]\n ");
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Ranga: %s", sBuffer, sRank);
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Punkty: %d", sBuffer, g_iPoints[client]);
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Czas spędzony na serwerze: %s", sBuffer, sTime);
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Zabójstwa: %d", sBuffer, g_iStats[client][0]);
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Headshoty: %d", sBuffer, g_iStats[client][1]);
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Assysty: %d", sBuffer, g_iStats[client][2]);
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Zgony: %d", sBuffer, g_iStats[client][3]);
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Podłożone bomby: %d", sBuffer, g_iStats[client][4]);
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Rozbrojone bomby: %d", sBuffer, g_iStats[client][5]);
					Format(sBuffer, sizeof(sBuffer), "%s\n➪ Uratowani zakładnicy: %d\n ", sBuffer, g_iStats[client][6]);
					Menu menu2 = new Menu(Stats_Handler);
					menu2.SetTitle(sBuffer);
					menu2.AddItem("", "» Zamknij");
					menu2.ExitBackButton = true;
					menu2.ExitButton = false;
					menu2.Display(client, MENU_TIME_FOREVER);
				}
			}
		}
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Ranks_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

void Points(int client, int status) {
	char sBuffer[512];
	if (status == 0) {
		Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » System punktacji ★ ]\n ");
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Poniżej został przedstawiony system punktacji Zwykłego Gracza.", sBuffer);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Aktualny status: %s\n ", sBuffer, IsPlayerVip(client) ? "VIP":"Zwykły Gracz");
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Zabójstwo: %d pkt.", sBuffer, g_iCvar[0]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Headshot: %d pkt.", sBuffer, g_iCvar[2]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Asysta: %d pkt.", sBuffer, g_iCvar[4]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Zgon: %d pkt.", sBuffer, g_iCvar[6]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Podłożenie bomby: %d pkt.", sBuffer, g_iCvar[8]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Rozbrojenie bomby: %d pkt.", sBuffer, g_iCvar[10]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Uratowanie zakładnika: %d pkt.\n ", sBuffer, g_iCvar[12]);
		Menu menu = new Menu(Points_Handler);
		menu.SetTitle(sBuffer);
		menu.AddItem("", "» Punktacja VIP'a");
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if (status == 1) {
		Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » System punktacji ★ ]\n ");
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Poniżej został przedstawiony system punktacji VIP'a.", sBuffer);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Aktualny status: %s\n ", sBuffer, IsPlayerVip(client) ? "VIP":"Zwykły Gracz");
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Zabójstwo: %d pkt.", sBuffer, g_iCvar[1]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Headshot: %d pkt.", sBuffer, g_iCvar[3]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Asysta: %d pkt.", sBuffer, g_iCvar[5]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Zgon: %d pkt.", sBuffer, g_iCvar[7]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Podłożenie bomby: %d pkt.", sBuffer, g_iCvar[9]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Rozbrojenie bomby: %d pkt.", sBuffer, g_iCvar[11]);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Uratowanie zakładnika: %d pkt.\n ", sBuffer, g_iCvar[13]);
		Menu menu = new Menu(Points2_Handler);
		menu.SetTitle(sBuffer);
		menu.AddItem("", "» Punktacja Zwykłego Gracza");
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
}

public int Points_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select:Points(client, 1);
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Player_Panel(client);
		}
		case MenuAction_End:delete menu;
	}
}

public int Points2_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select:Points(client, 0);
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Player_Panel(client);
		}
		case MenuAction_End:delete menu;
	}
}

public int List_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Player_Panel(client);
		}
		case MenuAction_End:delete menu;
	}
}

public int Stats_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Player_Panel(client);
		}
		case MenuAction_End:delete menu;
	}
}

void ShowRank(int client, int type) {
	DataPack Datapack = new DataPack();
	Datapack.WriteCell(client);
	char sQuery[512];
	switch (type) {
		case 0: {
			Format(sQuery, sizeof(sQuery), "SELECT `SteamID`, `Rank`, `Points` FROM `%s` WHERE `Points` >= '0' ORDER BY `Points`;", Table_Main);
			g_dbDatabase.Query(SQL_Rank_Handler, sQuery, Datapack);
		}
		case 1: {
			Format(sQuery, sizeof(sQuery), "SELECT `Nick`, `Time` FROM `%s` WHERE `Time` >= 0 ORDER BY `Time` DESC LIMIT 50;", Table_Main);
			g_dbDatabase.Query(SQL_TopTime_Handler, sQuery, Datapack);
		}
		case 2: {
			Format(sQuery, sizeof(sQuery), "SELECT `SteamID`, `Nick`, `Rank_Name`, `Points` FROM `%s` WHERE `Points` >= 0 ORDER BY `Points` DESC LIMIT 50;", Table_Main);
			g_dbDatabase.Query(SQL_TopPoints_Handler, sQuery, Datapack);
		}
	}
}

public void SQL_Rank_Handler(Database db, DBResultSet rs, const char[] sError, DataPack Datapack) {
	if (db == null || rs == null) {
		LogError("[ X Rangi -> Rank X ] Błąd podczas wczytywania rankingu: %s", sError);
		return;
	}
	
	Datapack.Reset();
	int client = Datapack.ReadCell();
	if (!IsValidClient(client))return;
	delete Datapack;
	
	int i;
	char sAuthIdQuery[64], sAuthId[64], sRank[64];
	GetClientAuthId(client, AuthId_Steam2, sAuthId, sizeof(sAuthId));
	int TotalPlayers = rs.RowCount;
	while (rs.HasResults && rs.FetchRow()) {
		i++;
		rs.FetchString(0, sAuthIdQuery, sizeof(sAuthIdQuery));
		if (StrEqual(sAuthIdQuery, sAuthId)) {
			Menu menu = new Menu(Rank_Handler);
			char sBuffer[512];
			g_arRanks[1].GetString(g_iRank[client], sRank, sizeof(sRank));
			Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Ranking ★ ]\n ");
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Nick: %N", sBuffer, client);
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Ranking: %d z %d", sBuffer, i, TotalPlayers);
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Ranga: %s", sBuffer, sRank);
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Punkty: %d\n ", sBuffer, g_iPoints[client]);
			menu.SetTitle(sBuffer);
			menu.AddItem("", "» Zamknij");
			menu.ExitButton = false;
			menu.ExitBackButton = true;
			menu.Display(client, MENU_TIME_FOREVER);
			break;
		}
	}
}

public int Rank_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Ranks_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

public void SQL_TopTime_Handler(Database db, DBResultSet rs, const char[] sError, DataPack Datapack) {
	if (db == null || rs == null) {
		LogError("[ X Rangi -> TopTime X ] Błąd podczas wczytywania topki: %s", sError);
		return;
	}
	
	Datapack.Reset();
	int client = Datapack.ReadCell();
	if (!IsValidClient(client))return;
	delete Datapack;
	int i;
	Menu menu = new Menu(TopTime_Handler);
	menu.SetTitle("[ ★ Rangi » Top Czasu ★ ]\n ");
	while (rs.HasResults && rs.FetchRow()) {
		i++;
		char sName[MAX_NAME_LENGTH], sBuffer[128], sTime[64];
		rs.FetchString(0, sName, sizeof(sName));
		int time = rs.FetchInt(1);
		FormatTimes(time, sTime, sizeof(sTime));
		Format(sBuffer, sizeof(sBuffer), "» #%d. %s - [ %s ]", i, sName, sTime);
		menu.AddItem("", sBuffer, ITEMDRAW_DISABLED);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int TopTime_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Ranks_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

public void SQL_TopPoints_Handler(Database db, DBResultSet rs, const char[] sError, DataPack Datapack) {
	if (db == null || rs == null) {
		LogError("[ X Rangi -> TopPoints X ] Błąd podczas wczytywania topki: %s", sError);
		return;
	}
	
	Datapack.Reset();
	int client = Datapack.ReadCell();
	if (!IsValidClient(client))return;
	delete Datapack;
	
	int i;
	char sName[MAX_NAME_LENGTH], sRank[64], sBuffer[128], sAuthId[64];
	Menu menu = new Menu(TopPoints_Handler);
	Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Top Punktów i Rang ★ ]\n ");
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Żeby zobaczyć statystyki gracza kliknij na niego.\n ", sBuffer);
	menu.SetTitle(sBuffer);
	while (rs.HasResults && rs.FetchRow()) {
		i++;
		rs.FetchString(0, sAuthId, sizeof(sAuthId));
		rs.FetchString(1, sName, sizeof(sName));
		rs.FetchString(2, sRank, sizeof(sRank));
		int points = rs.FetchInt(3);
		Format(sBuffer, sizeof(sBuffer), "» #%d. %s - [ %s | %d pkt ]", i, sName, sRank, points);
		menu.AddItem(sAuthId, sBuffer);
	}
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int TopPoints_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			char sItem[32], sQuery[256];
			menu.GetItem(position, sItem, sizeof(sItem));
			DataPack Datapack = new DataPack();
			Datapack.WriteCell(client);
			Format(sQuery, sizeof(sQuery), "SELECT `Nick`, `Kills`, `HeadShots`, `Assists`, `Deaths`, `Bomb_Planted`, `Bomb_Defused`, `Hostages` FROM `%s` WHERE `SteamID`='%s';", Table_Stats, sItem);
			g_dbDatabase.Query(SQL_Info_Handler, sQuery, Datapack);
		}
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Ranks_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

public void SQL_Info_Handler(Database db, DBResultSet rs, const char[] sError, DataPack Datapack) {
	if (db == null || rs == null) {
		LogError("[ X Rangi -> Info X ] Błąd podczas wczytywania danych: %s", sError);
		return;
	}
	
	Datapack.Reset();
	int client = Datapack.ReadCell();
	if (!IsValidClient(client))return;
	delete Datapack;
	
	char sBuffer[256], sName[MAX_NAME_LENGTH];
	Menu menu = new Menu(Info_Handler);
	if (rs.RowCount) {
		while (rs.FetchRow()) {
			rs.FetchString(0, sName, sizeof(sName));
			Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Informacje o Graczu ★ ]\n");
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Nick: %s", sBuffer, sName);
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Zabójstwa: %d", sBuffer, rs.FetchInt(0));
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Headshoty: %d", sBuffer, rs.FetchInt(1));
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Assysty: %d", sBuffer, rs.FetchInt(2));
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Zgony: %d", sBuffer, rs.FetchInt(3));
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Podłożone bomby: %d", sBuffer, rs.FetchInt(4));
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Rozbrojone bomby: %d", sBuffer, rs.FetchInt(5));
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Uratowani zakładnicy: %d\n ", sBuffer, rs.FetchInt(6));
			menu.SetTitle(sBuffer);
			menu.AddItem("", "» Zamknij");
			menu.ExitButton = false;
			menu.ExitBackButton = true;
			menu.Display(client, MENU_TIME_FOREVER);
			break;
		}
	}
}

public int Info_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				ShowRank(client, 2);
		}
		case MenuAction_End:delete menu;
	}
}

public Action Say_Command(int client, int args) {
	char sArg[16];
	GetCmdArg(1, sArg, sizeof(sArg));
	int value = StringToInt(sArg);
	if (g_bPoints[client][0] || g_bPoints[client][1]) {
		if (value <= 0) {
			CPrintToChat(client, "%s Liczba punktów musi być więsza od {lime}0{default}.", PluginTag_Info);
			g_bPoints[client][0] = false;
			g_bPoints[client][1] = false;
			return Plugin_Handled;
		}
	}
	
	if (g_bPoints[client][0]) {
		g_iPoints[g_iTarget[client]] += value;
		SQL_Update(g_iTarget[client], 2);
		CPrintToChat(client, "%s Pomyślnie dodano {lime}%d pkt.{default} graczowi {lightred}%N{default}.", PluginTag_Info, value, g_iTarget[client]);
		CheckRank(g_iTarget[client]);
	}
	if (g_bPoints[client][1]) {
		g_iPoints[g_iTarget[client]] -= value;
		SQL_Update(g_iTarget[client], 2);
		CPrintToChat(client, "%s Pomyślnie zabrano {lime}%d pkt.{default} graczowi {lightred}%N{default}.", PluginTag_Info, value, g_iTarget[client]);
		CheckRank(g_iTarget[client]);
	}
	
	g_bPoints[client][0] = false;
	g_bPoints[client][1] = false;
	return Plugin_Continue;
}

public Action AdminPanel_Command(int client, int args) {
	if (!HasAcces(client)) {
		CPrintToChat(client, "%s Do tej komendy ma dostęp tylko administracja.", PluginTag_Info);
		return;
	}
	char sBuffer[128];
	Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Panel Administracyjny ★ ]\n ");
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj, %N!", sBuffer, client);
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Wybierz jedną z dostępnych możliwości.\n ", sBuffer);
	Menu menu = new Menu(AdminPanel_Handler);
	menu.SetTitle(sBuffer);
	menu.AddItem("", "» Ustaw graczowi rangę.");
	menu.AddItem("", "» Zresetuj graczowi rangę oraz statystyki.");
	menu.AddItem("", "» Dodaj graczowi punkty.");
	menu.AddItem("", "» Zabierz graczowi punkty.");
	menu.AddItem("", "» Przeprowadź całkowity reset.\n ");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int AdminPanel_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select:AdminAction(client, position);
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Ranks_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

void AdminAction(int client, int action) {
	char sBuffer[256], sId[16];
	if (action == 0) {
		Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Ustawianie Rangi ★ ]\n ");
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj, %N!", sBuffer, client);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Wybierz dowolnego gracza.\n ", sBuffer);
		Menu menu = new Menu(SetRank_Handler);
		menu.SetTitle(sBuffer);
		LoopClients(i) {
			Format(sBuffer, sizeof(sBuffer), "» %N", i);
			Format(sId, sizeof(sId), "%d", GetClientSerial(i));
			menu.AddItem(sId, sBuffer);
		}
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if (action == 1) {
		Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Reset Gracza ★ ]\n ");
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj, %N!", sBuffer, client);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Wybierz dowolnego gracza.\n ", sBuffer);
		Menu menu = new Menu(ResetPlayer_Handler);
		menu.SetTitle(sBuffer);
		LoopClients(i) {
			Format(sBuffer, sizeof(sBuffer), "» %N", i);
			Format(sId, sizeof(sId), "%d", GetClientSerial(i));
			menu.AddItem(sId, sBuffer);
		}
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if (action == 2) {
		Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Dodawanie Punktów ★ ]\n ");
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj, %N!", sBuffer, client);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Wybierz dowolnego gracza.\n ", sBuffer);
		Menu menu = new Menu(AddPoints_Handler);
		menu.SetTitle(sBuffer);
		LoopClients(i) {
			Format(sBuffer, sizeof(sBuffer), "» %N", i);
			Format(sId, sizeof(sId), "%d", GetClientSerial(i));
			menu.AddItem(sId, sBuffer);
		}
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if (action == 3) {
		Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Zabieranie Punktów ★ ]\n ");
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj, %N!", sBuffer, client);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Wybierz dowolnego gracza.\n ", sBuffer);
		Menu menu = new Menu(RemovePoints_Handler);
		menu.SetTitle(sBuffer);
		LoopClients(i) {
			Format(sBuffer, sizeof(sBuffer), "» %N", i);
			Format(sId, sizeof(sId), "%d", GetClientSerial(i));
			menu.AddItem(sId, sBuffer);
		}
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else if (action == 4) {
		Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Całkowity Reset ★ ]\n ");
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj, %N!", sBuffer, client);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Czy na pewno chcesz przeprowadzić całkowity reset?", sBuffer);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Spowoduje on reset tabeli w bazie danych.", sBuffer);
		Format(sBuffer, sizeof(sBuffer), "%s\n➪ Tej akcji nie można cofnąć.", sBuffer);
		Menu menu = new Menu(ResetAll_Handler);
		menu.SetTitle(sBuffer);
		menu.AddItem("", "» Tak");
		menu.AddItem("", "» Nie");
		menu.ExitBackButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
}

public int SetRank_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			char sItem[16], sBuffer[128], sRank[64];
			menu.GetItem(position, sItem, sizeof(sItem));
			int id = GetClientFromSerial(StringToInt(sItem));
			g_iTarget[client] = id;
			Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Ustawianie Rangi ★ ]\n ");
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj, %N!", sBuffer, client);
			Format(sBuffer, sizeof(sBuffer), "%s\n➪ Wybierz range, którą chcesz ustawić.\n ", sBuffer);
			Menu menu2 = new Menu(SetRank2_Handler);
			menu2.SetTitle(sBuffer);
			for (int i = 0; i < g_arRanks[0].Length; i++) {
				g_arRanks[1].GetString(i, sRank, sizeof(sRank));
				IntToString(i, sItem, sizeof(sItem));
				Format(sBuffer, sizeof(sBuffer), "» %s ", sRank);
				menu2.AddItem(sItem, sBuffer);
			}
			if (menu2.ItemCount == 0)
				menu2.AddItem("", "» Brak rang na serwerze.", ITEMDRAW_DISABLED);
			menu2.Display(client, MENU_TIME_FOREVER);
		}
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				AdminPanel_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

public int SetRank2_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			char sItem[16];
			menu.GetItem(position, sItem, sizeof(sItem));
			int rank = StringToInt(sItem);
			g_iPoints[g_iTarget[client]] = g_arRanks[2].Get(rank);
			g_iRank[g_iTarget[client]] = rank;
			PrepareOverlay(g_iTarget[client], rank);
			SQL_Update(client, 0);
			SQL_Update(client, 2);
			CPrintToChat(client, "%s Ranga została pomyślnie ustawiona.", PluginTag_Info);
		}
		case MenuAction_End:delete menu;
	}
}

public int ResetPlayer_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			char sItem[16];
			menu.GetItem(position, sItem, sizeof(sItem));
			int id = GetClientFromSerial(StringToInt(sItem));
			Reset(id);
			for (int j = 0; j < 5; j++)
			SQL_Update(id, j);
			CheckRank(id);
			CPrintToChat(client, "%s Reset na graczu został przeprowadzony pomyślnie.", PluginTag_Info);
		}
		case MenuAction_End:delete menu;
	}
}

public int AddPoints_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			char sItem[16];
			menu.GetItem(position, sItem, sizeof(sItem));
			int id = GetClientFromSerial(StringToInt(sItem));
			g_iTarget[client] = id;
			CPrintToChat(client, "%s Wpisz na czacie ilość punktów do dodania.", PluginTag_Info);
			g_bPoints[client][0] = true;
		}
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				AdminPanel_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

public int RemovePoints_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			char sItem[16];
			menu.GetItem(position, sItem, sizeof(sItem));
			int id = GetClientFromSerial(StringToInt(sItem));
			g_iTarget[client] = id;
			CPrintToChat(client, "%s Wpisz na czacie ilość punktów do zabrania.", PluginTag_Info);
			g_bPoints[client][1] = true;
		}
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				AdminPanel_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

public int ResetAll_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			switch (position) {
				case 0: {
					char sQuery[256];
					Format(sQuery, sizeof(sQuery), "DELETE FROM `%s`", Table_Main);
					g_dbDatabase.Query(SQL_ResetAll_Handler, sQuery, 0);
					Format(sQuery, sizeof(sQuery), "DELETE FROM `%s`", Table_Stats);
					g_dbDatabase.Query(SQL_ResetAll_Handler, sQuery, 0);
					LoopClients(i) {
						Reset(i);
						SQL_InsertPlayer(i, 0);
						SQL_InsertPlayer(i, 1);
						CheckRank(i);
					}
				}
				case 1:CPrintToChat(client, "%s Akcja została anulowana.", PluginTag_Info);
			}
		}
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				AdminPanel_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

public void SQL_ResetAll_Handler(Database db, DBResultSet rs, const char[] sError, DataPack Datapack) {
	if (db == null || rs == null) {
		LogError("[ X Rangi -> ResetAll X ] Błąd podczas usuwania danych: %s", sError);
		return;
	}
}

public Action Hud_Command(int client, int args) {
	if (g_iCvar[16] == 0) {
		CPrintToChat(client, "%s Hud został wyłączony przez Własciciela Serwera.", PluginTag_Info);
		return;
	}
	char sBuffer[256];
	Format(sBuffer, sizeof(sBuffer), "[ ★ Rangi » Wybór Hudu ★ ]\n ");
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Witaj %N!", sBuffer, client);
	Format(sBuffer, sizeof(sBuffer), "%s\n➪ Wybierz typ hudu, który będzie ci najbardziej odpowiadać.\n ", sBuffer);
	Menu menu = new Menu(Hud_Handler);
	menu.SetTitle(sBuffer);
	menu.AddItem("", "» Wyłącz Hud");
	menu.AddItem("", "» Środek ekranu");
	menu.AddItem("", "» Nad czatem");
	Format(sBuffer, sizeof(sBuffer), "» %s overlaye.\n ", g_iOverlay[client] == 1 ? "Wyłącz":"Włącz");
	menu.AddItem("", sBuffer);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Hud_Handler(Menu menu, MenuAction action, int client, int position) {
	switch (action) {
		case MenuAction_Select: {
			switch (position) {
				case 0: {
					g_iHud[client] = 0;
					CPrintToChat(client, "%s Hud został {lightred}wyłączony{default}.", PluginTag_Info);
				}
				case 1: {
					CPrintToChat(client, "%s Ustawiono pozycję hudu na {lime}środku ekranu{default}.", PluginTag_Info);
					g_iHud[client] = 1;
				}
				case 2: {
					CPrintToChat(client, "%s Ustawiono pozycję hudu {lime}nad czatem{default}.", PluginTag_Info);
					g_iHud[client] = 2;
				}
				case 3: {
					g_iOverlay[client] = g_iOverlay[client] == 1 ? 0:1;
					CPrintToChat(client, "%s Overlaye zostały %s{default}.", PluginTag_Info, g_iOverlay[client] == 1 ? "{lime}włączone":"{lightred}wyłączone");
				}
			}
			SQL_Update(client, 3);
			Hud_Command(client, 0);
		}
		case MenuAction_Cancel: {
			if (position == MenuCancel_ExitBack)
				Ranks_Command(client, 0);
		}
		case MenuAction_End:delete menu;
	}
}

/* [ Events ] */
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	if (CountPlayers() < g_iCvar[18])
		return Plugin_Continue;
	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int assister = GetClientOfUserId(event.GetInt("assister"));
	bool headshot = event.GetBool("headshot");
	if (!IsValidClient(attacker) || !IsValidClient(client))
		return Plugin_Continue;
	
	if (GetClientTeam(client) == GetClientTeam(attacker))
		return Plugin_Continue;
	
	int score;
	if (IsValidClient(assister)) {
		g_iStats[assister][2]++;
		score = IsPlayerVip(assister) ? g_iCvar[5]:g_iCvar[4];
		g_iPoints[assister] += score;
	}
	
	g_iStats[attacker][0]++;
	g_iStats[client][3]++;
	
	score = IsPlayerVip(client) ? g_iCvar[7]:g_iCvar[6];
	g_iPoints[client] += score;
	
	if (g_iPoints[client] < 0)
		g_iPoints[client] = 0;
	CPrintToChat(client, "%s Straciłeś {lightred}%d pkt.{default} za zgon.", PluginTag_Info, score);
	
	if (headshot) {
		g_iStats[attacker][1]++;
		score = IsPlayerVip(attacker) ? g_iCvar[3]:g_iCvar[2];
		g_iPoints[attacker] += score;
		CPrintToChat(attacker, "%s Otrzymałeś {lime}%d pkt.{default} za HeadShota!", PluginTag_Info, score);
	}
	else {
		score = IsPlayerVip(attacker) ? g_iCvar[1]:g_iCvar[0];
		g_iPoints[attacker] += score;
		CPrintToChat(attacker, "%s Otrzymałeś {lime}%d pkt.{default} za zabójstwo przeciwnika !", PluginTag_Info, score);
	}
	SQL_Update(attacker, 1);
	SQL_Update(attacker, 2);
	CheckRank(attacker);
	SQL_Update(client, 1);
	SQL_Update(client, 2);
	CheckRank(client);
	return Plugin_Continue;
}

public Action Event_BombPlanted(Event event, const char[] name, bool dontBroadcast) {
	if (CountPlayers() < g_iCvar[18])
		return Plugin_Continue;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(client))return Plugin_Continue;
	
	g_iStats[client][4]++;
	int score;
	score = IsPlayerVip(client) ? g_iCvar[9]:g_iCvar[8];
	g_iPoints[client] += score;
	CPrintToChat(client, "%s Otrzymałeś {lime}%d pkt.{default} za podłożenie bomby !", PluginTag_Info, score);
	SQL_Update(client, 1);
	SQL_Update(client, 2);
	CheckRank(client);
	return Plugin_Continue;
}

public Action Event_BombDefused(Event event, const char[] name, bool dontBroadcast) {
	if (CountPlayers() < g_iCvar[18])
		return Plugin_Continue;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(client))return Plugin_Continue;
	
	g_iStats[client][5]++;
	int score;
	score = IsPlayerVip(client) ? g_iCvar[11]:g_iCvar[10];
	g_iPoints[client] += score;
	CPrintToChat(client, "%s Otrzymałeś {lime}%d pkt.{default} za rozbrojenie bomby !", PluginTag_Info, score);
	SQL_Update(client, 1);
	SQL_Update(client, 2);
	CheckRank(client);
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if (CountPlayers() < g_iCvar[18])
		return Plugin_Continue;
	int winner = event.GetInt("winner");
	int score;
	LoopClients(i) {
		score = IsPlayerVip(i) ? g_iCvar[15]:g_iCvar[14];
		if (GetClientTeam(i) == winner) {
			g_iPoints[i] += score;
			CPrintToChat(i, "%s Otrzymałeś {lime}%d pkt.{default} za wygraną rundę !", PluginTag_Info, score);
			SQL_Update(i, 1);
			SQL_Update(i, 2);
			CheckRank(i);
		}
	}
	return Plugin_Continue;
}

public Action Event_HostageRescued(Event event, const char[] name, bool dontBroadcast) {
	if (CountPlayers() < g_iCvar[18])
		return Plugin_Continue;
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(client))return Plugin_Continue;
	
	int score;
	score = IsPlayerVip(client) ? g_iCvar[13]:g_iCvar[12];
	g_iStats[client][6]++;
	g_iPoints[client] += score;
	
	CPrintToChat(client, "%s Otrzymałeś {lime}%d pkt.{default} za uratowanie zakładnika !", PluginTag_Info, score);
	SQL_Update(client, 1);
	SQL_Update(client, 2);
	CheckRank(client);
	return Plugin_Continue;
}

public Action Event_RoundStart(Event event, const char[] sName, bool bDontBroadcast) {
	if (CountPlayers() < g_iCvar[18])
		CPrintToChatAll("%s Punkty nie są liczone. Na serwerze nie ma {lime}%d{default} osób", PluginTag_Info, g_iCvar[18]);
}

/* [ Database Actions ] */
public void SQL_Connect_Handler(Database db, const char[] sError, any data) {
	if (g_dbDatabase != null)
		return;
	if (db == null)
		SetFailState("[ X Rangi -> Connect X ] Błąd podczas połączenia z bazą: %s", sError);
	
	char sQuery[] = 
	"CREATE TABLE IF NOT EXISTS `"...Table_Main..."` (\
				`SteamID` VARCHAR(64) NOT NULL,\
				`Nick` VARCHAR(64) NOT NULL,\
				`Rank` INT NOT NULL,\
				`Rank_Name` VARCHAR(64) NOT NULL,\
				`Points` INT NOT NULL,\
				`Hud` INT NOT NULL,\
				`Time` INT NOT NULL,\
				`Overlay` INT NOT NULL,\
				UNIQUE KEY `SteamID` (`SteamID`)\
			)ENGINE = InnoDB DEFAULT CHARSET = utf8 COLLATE = utf8_polish_ci;";
	db.SetCharset("utf8mb4");
	db.Query(SQL_Init1_Handler, sQuery, 0, DBPrio_High);
	
	char sQuery2[] = 
	"CREATE TABLE IF NOT EXISTS `"...Table_Stats..."` (\
				`SteamID` VARCHAR(64) NOT NULL,\
				`Nick` VARCHAR(64) NOT NULL,\
				`Kills` INT NOT NULL,\
				`HeadShots` INT NOT NULL,\
				`Assists` INT NOT NULL,\
				`Deaths` INT NOT NULL,\
				`Bomb_Planted` INT NOT NULL,\
				`Bomb_Defused` INT NOT NULL,\
				`Hostages` INT NOT NULL,\
				UNIQUE KEY `SteamID` (`SteamID`)\
			)ENGINE = InnoDB DEFAULT CHARSET = utf8 COLLATE = utf8_polish_ci;";
	db.SetCharset("utf8mb4");
	db.Query(SQL_Init2_Handler, sQuery2, 0, DBPrio_High);
	
	g_dbDatabase = db;
}

public void SQL_Init1_Handler(Database db, DBResultSet rs, const char[] sError, any data) {
	if (db == null || rs == null)
		SetFailState("[ X Rangi -> Table_Main X ] Nie udało się utworzyć tabeli: %s", sError);
}

public void SQL_Init2_Handler(Database db, DBResultSet rs, const char[] sError, any data) {
	if (db == null || rs == null)
		SetFailState("[ X Rangi -> Table_Stats X ] Nie udało się utworzyć tabeli: %s", sError);
}

void SQL_PrepareLoadData(int client) {
	if (!IsValidClient(client))return;
	
	if (g_dbDatabase == null) {
		LogError("[ X Rangi -> PrepareLoadData X ] Wystąpił problem podczas wszytywania danych gracza...");
		CPrintToChat(client, "%s Wystąpił problem podczas wczytywania danych...", PluginTag_Info);
	}
	else {
		char sQuery[1024], sAuthId[64];
		GetClientAuthId(client, AuthId_Steam2, sAuthId, sizeof(sAuthId));
		Format(sQuery, sizeof(sQuery), "SELECT `Rank`, `Points`, `Hud`, `Time`, `Overlay` FROM `%s` WHERE `SteamID`='%s';", Table_Main, sAuthId);
		g_dbDatabase.Query(SQL_LoadMain_Handler, sQuery, client);
		Format(sQuery, sizeof(sQuery), "SELECT `Kills`, `HeadShots`, `Assists`, `Deaths`, `Bomb_Planted`, `Bomb_Defused`, `Hostages` FROM `%s` WHERE `SteamID`='%s';", Table_Stats, sAuthId);
		g_dbDatabase.Query(SQL_LoadStats_Handler, sQuery, client);
	}
}

public void SQL_LoadMain_Handler(Database db, DBResultSet rs, const char[] sError, any client) {
	if (db == null || rs == null) {
		LogError("[ X Rangi -> LoadMain X ] Błąd podczas wczytywania danych: %s", sError);
		return;
	}
	if (rs.RowCount) {
		while (rs.FetchRow()) {
			g_iRank[client] = rs.FetchInt(0);
			g_iPoints[client] = rs.FetchInt(1);
			g_iHud[client] = rs.FetchInt(2);
			g_iTime[client] = rs.FetchInt(3);
			g_iOverlay[client] = rs.FetchInt(4);
		}
		g_bIsDataLoaded[client][0] = true;
	}
	else
		SQL_InsertPlayer(client, 0);
	
	if (IsClientConnected(client)) {
		CheckRank(client);
		char sAuthId[64], sRank[64];
		GetClientAuthId(client, AuthId_Steam2, sAuthId, sizeof(sAuthId));
		g_arRanks[1].GetString(g_iRank[client], sRank, sizeof(sRank));
		LogToFileEx(g_sLogFile, "[ Rangi -> Main ] [ Wejście ]	| %N (%s) przy wejściu posiadał: rangę %s (%d), %d punktów, %d minut", client, sAuthId, sRank, g_iRank[client], g_iPoints[client], g_iTime[client]);
	}
}

public void SQL_LoadStats_Handler(Database db, DBResultSet rs, const char[] sError, any client) {
	if (db == null || rs == null) {
		LogError("[ X Rangi -> LoadStats X ] Błąd podczas wczytywania danych: %s", sError);
		return;
	}
	if (rs.RowCount) {
		while (rs.FetchRow()) {
			for (int i = 0; i < 7; i++)
			g_iStats[client][i] = rs.FetchInt(i);
		}
		g_bIsDataLoaded[client][1] = true;
	}
	else
		SQL_InsertPlayer(client, 1);
	
	if (IsClientConnected(client)) {
		char sAuthId[64];
		GetClientAuthId(client, AuthId_Steam2, sAuthId, sizeof(sAuthId));
		LogToFileEx(g_sLogFile, "[ Rangi -> Stats ] [ Wejście ]	| %N (%s) przy wejściu posiadał: %d zabójstw, %d headshotów, %d assyst, %d śmierci, %d podłożonych bomb, %d rozbrojonych bomb, %d uratowanych zakładników.", client, sAuthId, g_iStats[client][0], g_iStats[client][1], g_iStats[client][2], g_iStats[client][3], g_iStats[client][4], g_iStats[client][5], g_iStats[client][6]);
	}
}

void SQL_InsertPlayer(int client, int type) {
	if (g_dbDatabase == null || !IsValidClient(client))
		return;
	
	char sQuery[512], sAuthId[64], sName[MAX_NAME_LENGTH], sSafeName[MAX_NAME_LENGTH * 2], sRank[64];
	g_arRanks[1].GetString(g_iRank[client], sRank, sizeof(sRank));
	GetClientName(client, sName, MAX_NAME_LENGTH);
	g_dbDatabase.Escape(sName, sSafeName, sizeof(sSafeName));
	GetClientAuthId(client, AuthId_Steam2, sAuthId, sizeof(sAuthId));
	if (type == 0 && !g_bIsDataLoaded[client][0]) {
		Format(sQuery, sizeof(sQuery), "INSERT INTO `%s` (`SteamID`, `Nick`, `Rank`, `Rank_Name`, `Points`, `Hud`, `Time`, `Overlay`) VALUES ('%s', N'%s', '%d', '%s', '%d', '%d', '%d', '%d') ON DUPLICATE KEY UPDATE `Rank`=VALUES(`Rank`), `Points`=VALUES(`Points`), `Hud`=VALUES(`Hud`), `Time`=VALUES(`Time`), `Overlay`=VALUES(`Overlay`);", Table_Main, sAuthId, sSafeName, g_iRank[client], sRank, g_iPoints[client], g_iHud[client], g_iTime[client], g_iOverlay[client]);
		g_dbDatabase.Query(SQL_Main_Handler, sQuery, client);
	}
	else if (type == 1 && !g_bIsDataLoaded[client][1]) {
		Format(sQuery, sizeof(sQuery), "INSERT INTO `%s` (`SteamID`, `Nick`, `Kills`, `HeadShots`, `Assists`, `Deaths`, `Bomb_Planted`, `Bomb_Defused`, `Hostages`) VALUES ('%s', N'%s', '%d', '%d', '%d', '%d', '%d', '%d', '%d') ON DUPLICATE KEY UPDATE `Kills`=VALUES(`Kills`), `HeadShots`=VALUES(`HeadShots`), `Assists`=VALUES(`Assists`), `Bomb_Planted`=VALUES(`Bomb_Planted`), `Bomb_Defused`=VALUES(`Bomb_Defused`), `Hostages`=VALUES(`Hostages`);", Table_Stats, sAuthId, sSafeName, g_iStats[client][0], g_iStats[client][1], g_iStats[client][2], g_iStats[client][3], g_iStats[client][4], g_iStats[client][5], g_iStats[client][6]);
		g_dbDatabase.Query(SQL_Stats_Handler, sQuery, client);
	}
}

void SQL_Update(int client, int type) {
	if (g_dbDatabase == null || !IsValidClient(client))
		return;
	
	char sQuery[512], sAuthId[64], sRank[64];
	g_arRanks[1].GetString(g_iRank[client], sRank, sizeof(sRank));
	GetClientAuthId(client, AuthId_Steam2, sAuthId, sizeof(sAuthId));
	if (type == 0 && g_bIsDataLoaded[client][0]) {
		Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET `Rank`='%d', `Rank_Name`='%s' WHERE `SteamID`='%s';", Table_Main, g_iRank[client], sRank, sAuthId);
		g_dbDatabase.Query(SQL_Main_Handler, sQuery, client);
	}
	else if (type == 1 && g_bIsDataLoaded[client][1]) {
		Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET `Kills`='%d', `HeadShots`='%d', `Assists`='%d',`Deaths`='%d', `Bomb_Planted`='%d', `Bomb_Defused`='%d', `Hostages`='%d' WHERE `SteamID`='%s';", Table_Stats, g_iStats[client][0], g_iStats[client][1], g_iStats[client][2], g_iStats[client][3], g_iStats[client][4], g_iStats[client][5], g_iStats[client][6], sAuthId);
		g_dbDatabase.Query(SQL_Stats_Handler, sQuery, client);
	}
	else if (type == 2 && g_bIsDataLoaded[client][0]) {
		Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET `Points`='%d' WHERE `SteamID`='%s';", Table_Main, g_iPoints[client], sAuthId);
		g_dbDatabase.Query(SQL_Main_Handler, sQuery, client);
	}
	else if (type == 3 && g_bIsDataLoaded[client][0]) {
		Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET `Hud`='%d', `Overlay`='%d' WHERE `SteamID`='%s';", Table_Main, g_iHud[client], g_iOverlay[client], sAuthId);
		g_dbDatabase.Query(SQL_Main_Handler, sQuery, client);
	}
	else if (type == 4 && g_bIsDataLoaded[client][0]) {
		Format(sQuery, sizeof(sQuery), "UPDATE `%s` SET `Time`='%d' WHERE `SteamID`='%s';", Table_Main, g_iTime[client], sAuthId);
		g_dbDatabase.Query(SQL_Main_Handler, sQuery, client);
	}
}

public void SQL_Main_Handler(Database db, DBResultSet results, const char[] sError, any client) {
	if (db == null || results == null) {
		LogError("[ X Rangi -> Main X ] Błąd podczas zapisywania danych: %s", sError);
		return;
	}
	g_bIsDataLoaded[client][0] = true;
}

public void SQL_Stats_Handler(Database db, DBResultSet results, const char[] sError, any client) {
	if (db == null || results == null) {
		LogError("[ X Rangi -> Stats X ] Błąd podczas zapisywania danych: %s", sError);
		return;
	}
	g_bIsDataLoaded[client][1] = true;
}

/* [ Timers ] */
public Action Timer_UpdateStatus(Handle hTimer) {
	if (g_iCvar[16] == 0)
		return Plugin_Stop;
	char sBuffer[512], sRank[64];
	LoopClients(i) {
		if (g_iHud[i] == 1) {
			if (IsPlayerAlive(i)) {
				g_arRanks[1].GetString(g_iRank[i], sRank, sizeof(sRank));
				Format(sBuffer, sizeof(sBuffer), "<font color='#ff9933'>» Ranga:</font> %s", sRank);
				if (g_iRank[i] == g_arRanks[0].Length - 1)
					Format(sBuffer, sizeof(sBuffer), "%s\n<font color='#ff9933'>» Punkty:</font> %d", sBuffer, g_iPoints[i]);
				else
					Format(sBuffer, sizeof(sBuffer), "%s\n<font color='#ff9933'>» Punkty:</font> %d/%d", sBuffer, g_iPoints[i], g_arRanks[2].Get(g_iRank[i] + 1));
			}
			else {
				int spect = GetEntProp(i, Prop_Send, "m_iObserverMode");
				if (spect == 4 || spect == 5) {
					int target = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
					if (target != -1 && IsValidClient(target)) {
						g_arRanks[1].GetString(g_iRank[target], sRank, sizeof(sRank));
						Format(sBuffer, sizeof(sBuffer), "<font color='#ff9933'>» Ranga:</font> %s", sRank);
						if (g_iRank[i] == g_arRanks[0].Length - 1)
							Format(sBuffer, sizeof(sBuffer), "%s\n<font color='#ff9933'>» Punkty:</font> %d", sBuffer, g_iPoints[target]);
						else
							Format(sBuffer, sizeof(sBuffer), "%s\n<font color='#ff9933'>» Punkty:</font> %d/%d", sBuffer, g_iPoints[target], g_arRanks[2].Get(g_iRank[target] + 1));
					}
				}
			}
			PrintHintText(i, sBuffer);
		}
		else if (g_iHud[i] == 2) {
			if (IsPlayerAlive(i)) {
				g_arRanks[1].GetString(g_iRank[i], sRank, sizeof(sRank));
				Format(sBuffer, sizeof(sBuffer), "» Ranga: %s", sRank);
				if (g_iRank[i] == g_arRanks[0].Length - 1)
					Format(sBuffer, sizeof(sBuffer), "%s\n» Punkty: %d", sBuffer, g_iPoints[i]);
				else
					Format(sBuffer, sizeof(sBuffer), "%s\n» Punkty: %d/%d", sBuffer, g_iPoints[i], g_arRanks[2].Get(g_iRank[i] + 1));
				SetHudTextParams(0.03, -0.33, 1.5, 6, 231, 1, 255, 0, 10.0, 0.0, 0.0);
				ShowSyncHudText(i, g_hHud, sBuffer);
			}
			else {
				int spect = GetEntProp(i, Prop_Send, "m_iObserverMode");
				if (spect == 4 || spect == 5) {
					int target = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
					if (target != -1 && IsValidClient(target)) {
						g_arRanks[1].GetString(g_iRank[target], sRank, sizeof(sRank));
						Format(sBuffer, sizeof(sBuffer), "★ Ranga: %s", sRank);
						if (g_iRank[i] == g_arRanks[0].Length - 1)
							Format(sBuffer, sizeof(sBuffer), "%s\n» Punkty: %d", sBuffer, g_iPoints[target]);
						else
							Format(sBuffer, sizeof(sBuffer), "%s\n» Punkty: %d/%d", sBuffer, g_iPoints[target], g_arRanks[2].Get(g_iRank[target] + 1));
						SetHudTextParams(0.03, -0.33, 1.5, 6, 231, 1, 255, 0, 10.0, 0.0, 0.0);
						ShowSyncHudText(i, g_hHud, sBuffer);
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action Timer_AddMinute(Handle hTimer) {
	LoopClients(i) {
		g_iTime[i]++;
		SQL_Update(i, 4);
	}
}

public Action Timer_AuthorInfo(Handle hTimer) {
	CPrintToChatAll("%s Plugin został napisany przez {lime}Pawła{default}.", PluginTag_Info);
	CPrintToChatAll("%s Plugin jest udostepniony za darmo na {lime}Go-Code.pl{default}.", PluginTag_Info);
}

/* [ Helpers ] */
void CheckRank(int client) {
	int max_ranks = g_arRanks[0].Length - 1;
	bool bRankUp = false;
	bool bRankDown = false;
	if (g_iRank[client] >= max_ranks) {
		g_iRank[client] = max_ranks;
		SQL_Update(client, 0);
		return;
	}
	while (g_iPoints[client] >= g_arRanks[2].Get(g_iRank[client] + 1)) {
		g_iRank[client]++;
		bRankUp = true;
	}
	while (g_iRank[client] > 0 && g_iPoints[client] < g_arRanks[2].Get(g_iRank[client] - 1)) {
		g_iRank[client]--;
		bRankDown = true;
	}
	char sRank[64];
	g_arRanks[1].GetString(g_iRank[client], sRank, sizeof(sRank));
	if (bRankUp) {
		if (g_iOverlay[client] == 1 && g_iCvar[17] != 3)
			PrepareOverlay(client, g_iRank[client]);
		PrecacheSound(RankUp, true);
		EmitSoundToClient(client, RankUp, _, _, _, _, 0.5);
		CPrintToChat(client, "%s Awansowałeś na rangę {lime}%s{default}.", PluginTag_Info, sRank);
		Call_StartForward(g_hRankUp);
		Call_PushCell(client);
		Call_PushCell(g_iRank[client]);
		Call_Finish();
		SQL_Update(client, 0);
	}
	if (bRankDown) {
		if (g_iOverlay[client] == 1 && g_iCvar[17] != 3)
			PrepareOverlay(client, g_iRank[client]);
		PrecacheSound(RankDown, true);
		EmitSoundToClient(client, RankDown, _, _, _, _, 0.5);
		CPrintToChat(client, "%s Spadłeś do rangi {lightred}%s{default}!", PluginTag_Info, sRank);
		Call_StartForward(g_hRankDown);
		Call_PushCell(client);
		Call_PushCell(g_iRank[client]);
		Call_Finish();
		SQL_Update(client, 0);
	}
}

void Reset(int client) {
	g_iHud[client] = 1;
	g_iOverlay[client] = 1;
	g_iTime[client] = 0;
	g_bIsDataLoaded[client][0] = false;
	g_bIsDataLoaded[client][1] = false;
	for (int i = 0; i < 7; i++)
	g_iStats[client][i] = 0;
	g_iPoints[client] = g_iCvar[20];
	g_iRank[client] = 0;
	g_iTarget[client] = 0;
}

public void OnThinkPost(int entity) {
	int iRank[MAXPLAYERS + 1];
	int m_iCompetitiveRanking = -1;
	
	if (m_iCompetitiveRanking == -1)
		m_iCompetitiveRanking = FindSendPropInfo("CCSPlayerResource", "m_iCompetitiveRanking");
	
	GetEntDataArray(entity, m_iCompetitiveRanking, iRank, MaxClients + 1);
	LoopClients(i) {
		if (g_iCvar[17] == 1)
			iRank[i] = g_iRank[i];
		else if (g_iCvar[17] == 2)
			iRank[i] = g_iRank[i] + 50;
		else if (g_iCvar[17] == 3)
			iRank[i] = g_iRank[i] + 70;
	}
	SetEntDataArray(entity, m_iCompetitiveRanking, iRank, MaxClients + 1);
}

void LoadConfig() {
	KeyValues kv = new KeyValues("Pawel Ranks - Config");
	char sPath[PLATFORM_MAX_PATH], sBuffer[128];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/Rangi/Config.cfg");
	if (!kv.ImportFromFile(sPath)) {
		if (!FileExists(sPath)) {
			if (GenerateConfig())
				LoadConfig();
			else
				SetFailState("[ X Rangi -> Config X ] Nie udało się utworzyć pliku konfiguracyjnego!");
			delete kv;
			return;
		}
		else {
			LogError("[ X Rangi -> Config X ] Aktualny plik konfiguracyjny jest uszkodzony! Trwa tworzenie nowego...");
			if (GenerateConfig())
				LoadConfig();
			else
				SetFailState("[ X Rangi -> Config X ] Nie udało się utworzyć pliku konfiguracyjnego!");
			delete kv;
			return;
		}
	}
	
	if (kv.JumpToKey("Ustawienia")) {
		g_iCvar[0] = kv.GetNum("points_for_kill");
		g_iCvar[1] = kv.GetNum("points_for_kill_vip");
		g_iCvar[2] = kv.GetNum("points_for_hs");
		g_iCvar[3] = kv.GetNum("points_for_hs_vip");
		g_iCvar[4] = kv.GetNum("points_for_assist");
		g_iCvar[5] = kv.GetNum("points_for_assist_vip");
		g_iCvar[6] = kv.GetNum("points_for_dead");
		g_iCvar[7] = kv.GetNum("points_for_dead_vip");
		g_iCvar[8] = kv.GetNum("points_for_plant");
		g_iCvar[9] = kv.GetNum("points_for_plant_vip");
		g_iCvar[10] = kv.GetNum("points_for_defuse");
		g_iCvar[11] = kv.GetNum("points_for_defuse_vip");
		g_iCvar[12] = kv.GetNum("points_for_hostage");
		g_iCvar[13] = kv.GetNum("points_for_hostage_vip");
		g_iCvar[14] = kv.GetNum("points_for_win");
		g_iCvar[15] = kv.GetNum("points_for_win_vip");
		g_iCvar[16] = kv.GetNum("hud_enabled");
		g_iCvar[17] = kv.GetNum("rank_type");
		g_iCvar[18] = kv.GetNum("min_players");
		g_iCvar[19] = kv.GetNum("chat_tag");
		g_iCvar[20] = kv.GetNum("start_points");
		kv.GoBack();
	}
	kv.GoBack();
	if (kv.JumpToKey("Rangi")) {
		if (g_iCvar[17] == 1 || g_iCvar[17] == 2) {
			if (kv.JumpToKey("Normalne")) {
				kv.GotoFirstSubKey();
				do {
					g_arRanks[0].Push(g_arRanks[0].Length + 1);
					kv.GetSectionName(sBuffer, sizeof(sBuffer));
					g_arRanks[1].PushString(sBuffer);
					g_arRanks[2].Push(kv.GetNum("points"));
					kv.GetString("tag_color", sBuffer, sizeof(sBuffer));
					g_arRanks[3].PushString(sBuffer);
					kv.GetString("chat_tag", sBuffer, sizeof(sBuffer));
					g_arRanks[4].PushString(sBuffer);
				}
				while (kv.GotoNextKey());
				kv.GoBack();
			}
			kv.GoBack();
		}
		else if (g_iCvar[17] == 3) {
			if (kv.JumpToKey("Dangerzone")) {
				kv.GotoFirstSubKey();
				do {
					g_arRanks[0].Push(g_arRanks[0].Length + 1);
					kv.GetSectionName(sBuffer, sizeof(sBuffer));
					g_arRanks[1].PushString(sBuffer);
					g_arRanks[2].Push(kv.GetNum("points"));
					kv.GetString("tag_color", sBuffer, sizeof(sBuffer));
					g_arRanks[3].PushString(sBuffer);
					kv.GetString("chat_tag", sBuffer, sizeof(sBuffer));
					g_arRanks[4].PushString(sBuffer);
				}
				while (kv.GotoNextKey());
				kv.GoBack();
			}
			kv.GoBack();
		}
		kv.GoBack();
	}
	kv.GoBack();
	delete kv;
}

bool GenerateConfig() {
	KeyValues kv = new KeyValues("Pawel Ranks - Config");
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/Rangi/Config.cfg");
	if (kv.JumpToKey("Ustawienia", true)) {
		kv.SetString("points_for_kill", "1");
		kv.SetString("points_for_kill_vip", "2");
		kv.SetString("points_for_hs", "2");
		kv.SetString("points_for_hs_vip", "3");
		kv.SetString("points_for_assist", "1");
		kv.SetString("points_for_assist_vip", "2");
		kv.SetString("points_for_dead", "-2");
		kv.SetString("points_for_dead_vip", "-1");
		kv.SetString("points_for_plant", "1");
		kv.SetString("points_for_plant_vip", "2");
		kv.SetString("points_for_defuse", "1");
		kv.SetString("points_for_defuse_vip", "2");
		kv.SetString("points_for_hostage", "1");
		kv.SetString("points_for_hostage_vip", "2");
		kv.SetString("points_for_win", "1");
		kv.SetString("points_for_win_vip", "2");
		kv.SetString("hud_enabled", "1");
		kv.SetString("rank_type", "1");
		kv.SetString("min_players", "5");
		kv.SetString("chat_tag", "1");
		kv.SetString("start_points", "1000");
		kv.GoBack();
	}
	kv.Rewind();
	bool result = kv.ExportToFile(sPath);
	delete kv;
	return result;
}

void PrepareOverlay(int client, int rank) {
	char sBuffer[128];
	Format(sBuffer, sizeof(sBuffer), "pawel_ranks/rank_%d.vtf", rank);
	ShowOverlay(client, sBuffer, 2.0);
}

void ArraysAction(int action) {
	switch (action) {
		case 0: {
			for (int i = 0; i < 5; i++)
			g_arRanks[i] = new ArrayList(64);
		}
		case 1: {
			for (int i = 0; i < 5; i++)
			g_arRanks[i].Clear();
		}
	}
}

public Action OnPlayerRunCmd(int client, int &iButtons, int &impulse, float vel[3], float angles[3], int &weapon) {
	static int iOButtons[MAXPLAYERS + 1];
	if (iButtons & IN_SCORE && !(iOButtons[client] & IN_SCORE)) {
		StartMessageOne("ServerRankRevealAll", client, USERMSG_BLOCKHOOKS);
		EndMessage();
	}
	iOButtons[client] = iButtons;
}

int CountPlayers() {
	int players = 0;
	LoopClients(i)
	if (GetClientTeam(i) == CS_TEAM_CT || GetClientTeam(i) == CS_TEAM_T)
		players++;
	
	return players;
}

void FormatTimes(int time, char[] newtime, int newtimesize) {
	char sHours[64], sMinutes[64];
	int hours;
	
	if (time > 60) {
		hours = time / 60;
		time = time % 60;
	}
	
	Format(sHours, sizeof(sHours), "%d", hours);
	
	if (time < 0)
		Format(sMinutes, sizeof(sMinutes), "0%d", time);
	else
		Format(sMinutes, sizeof(sMinutes), "%d", time);
	
	if (hours > 0)
		Format(newtime, newtimesize, "%s godz. %s min.", sHours, sMinutes);
	else if (time > 0)
		Format(newtime, newtimesize, "%s min.", sMinutes);
}

/* [ Chat Message ] */
#if defined _chat_processor_included
public Action CP_OnChatMessage(int & author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool & processcolors, bool & removecolors) {
	if (g_iCvar[19] == 0)
		return Plugin_Continue;
	
	char sColor[64], sTag[64];
	g_arRanks[3].GetString(g_iRank[author], sColor, sizeof(sColor));
	g_arRanks[4].GetString(g_iRank[author], sTag, sizeof(sTag));
	Format(name, MAXLENGTH_NAME, " %s%s »{teamcolor} %s", sColor, sTag, name);
	Format(message, MAXLENGTH_MESSAGE, "%s", message);
	return Plugin_Changed;
}
#endif

#if defined _scp_included
public Action OnChatMessage(int &client, Handle recipients, char[] name, char[] message) {
	if (g_iCvar[19] == 0)
		return Plugin_Continue;
	char sColor[32], sTag[32];
	g_arRanks[3].GetString(g_iRank[client], sColor, sizeof(sColor));
	g_arRanks[4].GetString(g_iRank[client], sTag, sizeof(sTag));
	Format(name, MAXLENGTH_NAME, " %s%s »\x01 %s", sColor, sTag, name);
	return Plugin_Changed;
}
#endif

/* [ Natives ] */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("pRanks_AddClientPoints", Native_AddClientPoints);
	CreateNative("pRanks_SetClientPoints", Native_SetClientPoints);
	CreateNative("pRanks_GetClientPoints", Native_GetClientPoints);
	CreateNative("pRanks_SetClientRank", Native_SetClientRank);
	CreateNative("pRanks_GetClientRank", Native_GetClientRank);
	CreateNative("pRanks_GetClientTime", Native_GetClientTime);
	CreateNative("pRanks_GetClientKills", Native_GetClientKills);
	CreateNative("pRanks_GetClientHS", Native_GetClientHeadshots);
	CreateNative("pRanks_GetClientAssists", Native_GetClientAssists);
	CreateNative("pRanks_GetClientDeaths", Native_GetClientDeaths);
	CreateNative("pRanks_GetClientBombPlants", Native_GetClientBombPlants);
	CreateNative("pRanks_GetClientBombDefuses", Native_GetClientBombDefuses);
	CreateNative("pRanks_GetClientHostages", Native_GetClientHostages);
	CreateNative("pRanks_GetRanksCount", Native_GetRanksCount);
	CreateNative("pRanks_GetPointsForRank", Native_GetPointsForRank);
	CreateNative("pRanks_GetRankName", Native_GetRankName);
	CreateNative("pRanks_GetRankChatTag", Native_GetRankChatTag);
	CreateNative("pRanks_GetRankChatColor", Native_GetRankChatColor);
	CreateNative("pRanks_GetRankId", Native_GetRankId);
	RegPluginLibrary("pRanks-Core");
	return APLRes_Success;
}

public int Native_AddClientPoints(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client)) {
		g_iPoints[client] += GetNativeCell(2);
		SQL_Update(client, 2);
		CheckRank(client);
		return 1;
	}
	return 0;
}

public int Native_SetClientPoints(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client)) {
		g_iPoints[client] = GetNativeCell(2);
		SQL_Update(client, 2);
		CheckRank(client);
		return 1;
	}
	return 0;
}

public int Native_GetClientPoints(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iPoints[client];
	return 0;
}

public int Native_SetClientRank(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client)) {
		g_iRank[client] = GetNativeCell(2);
		g_iPoints[client] = g_arRanks[2].Get(g_iRank[client]);
		SQL_Update(client, 0);
		SQL_Update(client, 2);
		CheckRank(client);
		return 1;
	}
	return 0;
}

public int Native_GetClientRank(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iRank[client];
	return 0;
}


public int Native_GetClientTime(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iTime[client];
	return 0;
}

public int Native_GetClientKills(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iStats[client][0];
	return 0;
}

public int Native_GetClientHeadshots(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iStats[client][1];
	return 0;
}

public int Native_GetClientAssists(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iStats[client][2];
	return 0;
}

public int Native_GetClientDeaths(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iStats[client][3];
	return 0;
}

public int Native_GetClientBombPlants(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iStats[client][4];
	return 0;
}

public int Native_GetClientBombDefuses(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iStats[client][5];
	return 0;
}

public int Native_GetClientHostages(Handle hPlugin, int numParams) {
	int client = GetNativeCell(1);
	if (IsValidClient(client))
		return g_iStats[client][6];
	return 0;
}

public int Native_GetRanksCount(Handle hPlugin, int numParams) {
	return g_arRanks[0].Length;
}

public int Native_GetPointsForRank(Handle hPlugin, int numParams) {
	return g_arRanks[2].Get(GetNativeCell(1));
}

public int Native_GetRankName(Handle hPlugin, int numParams) {
	char sBuffer[128];
	g_arRanks[1].GetString(GetNativeCell(1), sBuffer, sizeof(sBuffer));
	SetNativeString(2, sBuffer, GetNativeCell(3));
}

public int Native_GetRankChatTag(Handle hPlugin, int numParams) {
	char sBuffer[128];
	g_arRanks[4].GetString(GetNativeCell(1), sBuffer, sizeof(sBuffer));
	SetNativeString(2, sBuffer, GetNativeCell(3));
}

public int Native_GetRankChatColor(Handle hPlugin, int numParams) {
	char sBuffer[128];
	g_arRanks[3].GetString(GetNativeCell(1), sBuffer, sizeof(sBuffer));
	SetNativeString(2, sBuffer, GetNativeCell(3));
}

public int Native_GetRankId(Handle hPlugin, int numParams) {
	char sBuffer[128], sRank[128];
	GetNativeString(1, sBuffer, sizeof(sBuffer));
	for (int i = 0; i < g_arRanks[0].Length; i++) {
		g_arRanks[1].GetString(i, sRank, sizeof(sRank));
		if (StrEqual(sBuffer, sRank))
			return i;
	}
	return 0;
}
