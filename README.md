# Diagnostic PC

Script PowerShell qui fait le bilan de santé et de sécurité d'un poste Windows 11, à la manière d'un technicien support. Il affiche le résultat dans la console, signale les points d'attention et enregistre un rapport texte.

Projet réalisé dans le cadre de ma reconversion vers le support informatique et la cybersécurité.

## Ce que le script vérifie

| Domaine | Contrôle | Seuil d'alerte |
|---|---|---|
| Système | Nom du PC, édition de Windows, processeur, mémoire | Moins de 10 % de RAM libre |
| Disques | Espace libre de chaque disque local | Moins de 15 % d'espace libre |
| Réseau | Adresse IP, passerelle, puis tests box, Internet et DNS | Un des trois tests échoue |
| Démarrage | Date du dernier redémarrage | Plus de 7 jours |
| Journaux | Erreurs du journal Système sur 24 h | 20 erreurs ou plus |
| Antivirus | État de Windows Defender, âge des définitions, dernières analyses | Defender ou temps réel désactivé, définitions de plus de 3 jours, aucune analyse rapide depuis 14 jours |
| Pare-feu | État des profils Domaine, Privé et Public | Profil désactivé ou connexions entrantes autorisées par défaut |
| Mises à jour | Dernier correctif Windows installé | Plus de 45 jours |
| Comptes | Membres du groupe Administrateurs, comptes actifs | Compte Administrateur intégré ou Invité activé |
| Chiffrement | Protection du disque système | Disque non chiffré |

Le script ne modifie rien sur le poste : il se contente de lire.

## Utilisation

Ouvrir PowerShell **en administrateur** (nécessaire pour le contrôle du chiffrement), puis :

```powershell
cd chemin\vers\diagnostic-pc
powershell -ExecutionPolicy Bypass -File .\diagnostic.ps1
```

`-ExecutionPolicy Bypass` autorise l'exécution du script pour cette fois seulement, sans changer la stratégie d'exécution du poste.

Le rapport est enregistré dans le sous-dossier `rapports`, sous la forme `diagnostic_AAAA-MM-JJ_HHMM.txt`. Ce dossier est exclu du dépôt car les rapports contiennent des informations propres à la machine.

## Ce que j'ai appris

- Interroger Windows avec PowerShell : `Get-CimInstance`, `Get-NetIPConfiguration`, `Get-WinEvent`, `Get-MpComputerStatus`, `Get-NetFirewallProfile`, `Get-HotFix`, `Get-LocalUser`.
- Diagnostiquer une connexion couche par couche : la box, puis Internet, puis la résolution DNS.
- Pourquoi « Arrêter » ne remet pas le compteur de démarrage à zéro (démarrage rapide de Windows), d'où l'importance de demander un redémarrage.
- Repérer un groupe Windows par son SID (`S-1-5-32-544` pour Administrateurs) pour qu'un script fonctionne quelle que soit la langue du système.
- Les points de contrôle d'un audit de poste : antivirus, pare-feu, correctifs (Patch Tuesday), comptes à privilèges, chiffrement.
- Ne jamais lancer un script sans l'avoir lu, et ne pas publier de données propres à une machine.

## Environnement testé

Windows 11 Famille, Windows PowerShell 5.1.
