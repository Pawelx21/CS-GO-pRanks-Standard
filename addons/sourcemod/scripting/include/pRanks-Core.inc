/**
 * Dodaje graczowi punkty, zapisując natychmiastowo w bazie.
 * 
 * @param client		Index gracza.
 * @param points		Liczba punktów.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_AddClientPoints(int client, int points);

/**
 * Ustawia graczowi punkty, zapisując natychmiastowo w bazie.
 * 
 * @param client		Index gracza.
 * @param points		Liczba punktów.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_SetClientPoints(int client, int points);

/**
 * Pobiera ilość punktów gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClientPoints(int client, int points);

/**
 * Ustawia graczowi rangę i wymagane punkty, zapisując natychmiastowo w bazie.
 * 
 * @param client		Index gracza.
 * @param rank			Index rangi.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_SetClientRank(int client, int rank);

/**
 * Pobiera indeks rangi gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClientRank(int client);

/**
 * Pobiera minuty przegrane na serwerze przez gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClientTime(int client);

/**
 * Pobiera ilość zabójstw gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClientKills(int client);

/**
 * Pobiera ilość headshotów gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClientHS(int client);

/**
 * Pobiera ilość asyst gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClientAssists(int client);

/**
 * Pobiera ilość śmierci gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClientDeaths(int client);

/**
 * Pobiera ilość podłożonych bomb przez gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClientBombPlants(int client);

/**
 * Pobiera ilość rozbrojonych bomb przez gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClienBombDefuses(int client);

/**
 * Pobiera ilość uratowanych zakładników przez gracza.
 * 
 * @param client		Index gracza.
 * @return 				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
native bool pRanks_GetClientHostages(int client);

/**
 * Pobiera ilość rang na serwerze.
 *
 * @noreturn 
 */
native int pRanks_GetRanksCount();

/**
 * Pobiera wymaganą liczbę punktów na daną rangę.
 * 
 * @param rank			Index rangi.
 * @noreturn 
 */
native int pRanks_GetPointsForRank(int rank);

/**
 * Pobiera nazwę rangi.
 * 
 * @param rank			Index rangi.
 * @noreturn 
 */
native void pRanks_GetRankName(int rank);

/**
 * Pobiera tag na czacie rangi.
 * 
 * @param rank			Index rangi.
 * @noreturn 
 */
native void pRanks_GetRankChatTag(int rank);

/**
 * Pobiera kolor tagu na czacie rangi.
 * 
 * @param rank			Index rangi.
 * @noreturn 
 */
native void pRanks_GetRankChatColor(int rank);

/**
 * Pobiera index rangi na podstawie jej nazwy.
 * 
 * @param rank			Index rangi.
 * @noreturn 
 */
native int pRanks_GetRankId(char[] sRankName);

//////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Sprawdza czy gracz nie jest botem i jest prawidłowy.
 *
 * @param client		Index gracza.
 * @return				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
stock bool IsValidClient(int client) {
	if (client <= 0)return false;
	if (client > MaxClients)return false;
	if (!IsClientConnected(client))return false;
	if (IsFakeClient(client))return false;
	if (IsClientSourceTV(client))return false;
	return IsClientInGame(client);
}

/**
 * Sprawdza czy gracz jest Vipem.
 *
 * @param client		Index gracza.
 * @return				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
stock bool IsPlayerVip(int client) {
	if (GetUserFlagBits(client) & ADMFLAG_ROOT)return true;
	if (CheckCommandAccess(client, "sm_pVip", ADMFLAG_CUSTOM1, true))return true;
	return false;
}

/**
 * Sprawdza czy gracz ma dostęp do panelu administracyjnego.
 *
 * @param client		Index gracza.
 * @return				True w przypadku powodzenia, false w przeciwnym wypadku.
 */
stock bool HasAcces(int client) {
	if (GetUserFlagBits(client) & ADMFLAG_ROOT)return true;
	if (CheckCommandAccess(client, "sm_pAcces", ADMFLAG_CHEATS, true))return true;
	return false;
}

/**
 * Pobiera i robi precache dźwięku.
 *
 * @param sPath		Ścieżka do dźwięku z wykluczeniem folderu "sound"
 * @noreturn
 */
stock void PrecacheSoundAnyDownload(char[] sPath) {
	char sBuffer[256];
	Format(sBuffer, sizeof(sBuffer), "sound/%s", sPath);
	AddFileToDownloadsTable(sBuffer);
	
	PrecacheSound(sPath, true);
}

/**
 * Pobiera i robi precache overlaya.
 *
 * @param sPath		Ścieżka do overlaya z wykluczeniem folderu "materials"
 * @noreturn
 */
stock void PrecacheDecalAnyDownload(char[] sPath) {
	char sBuffer[256];
	Format(sBuffer, sizeof(sBuffer), "%s.vmt", sPath);
	PrecacheDecal(sBuffer, true);
	Format(sBuffer, sizeof(sBuffer), "materials/%s.vmt", sPath);
	AddFileToDownloadsTable(sBuffer);
	
	Format(sBuffer, sizeof(sBuffer), "%s.vtf", sPath);
	PrecacheDecal(sBuffer, true);
	Format(sBuffer, sizeof(sBuffer), "materials/%s.vtf", sPath);
	AddFileToDownloadsTable(sBuffer);
}

/**
 * Pokazuje overlaya na określony czas
 *
 * @param client	Index gracza.
 * @param sPath		Ścieżka do overlaya z wykluczeniem folderu "materials"
 * @param fTime		Czas przez jaki overlay ma się wyświetlać.
 * @noreturn
 */
stock void ShowOverlay(int client, char[] sPath, float fTime) {
	if (!IsValidClient(client))return;
	
	int flag = GetCommandFlags("r_screenoverlay") & (~FCVAR_CHEAT);
	SetCommandFlags("r_screenoverlay", flag);
	ClientCommand(client, "r_screenoverlay \"%s.vtf\"", sPath);
	
	CreateTimer(fTime, Timer_DeleteOverlay, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Usuwa overlaya z ekranu gracza.
 *
 * @noreturn
 */
stock Action Timer_DeleteOverlay(Handle hTimer, int userid) {
	int client = GetClientOfUserId(userid);
	if (!IsValidClient(client))return;
	int flag = GetCommandFlags("r_screenoverlay") & (~FCVAR_CHEAT);
	SetCommandFlags("r_screenoverlay", flag);
	ClientCommand(client, "r_screenoverlay \"\"");
} 