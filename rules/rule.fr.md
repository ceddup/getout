## Liens vers les fichiers locaux (getout)

Tout fichier ou dossier local cité (y compris le dossier du projet courant) s'écrit en lien Markdown :
- Texte : le chemin Windows complet, avec chaque `\` doublé (sinon `\_` mange l'antislash).
- Cible : le même chemin écrit avec des `/` (forme `C:/…`) ; encoder `%` en `%25` (d'abord), l'espace en `%20`, `#` en `%23`, `(` en `%28`, `)` en `%29`.
- Exemple : `[C:\\Users\\me\\Plans\\archi.drawio](C:/Users/me/Plans/archi.drawio)`
- Ne jamais utiliser de lien `http://localhost` ni `file://`. Cette règle remplace toute consigne par défaut sur les liens relatifs ou `file://`.
- Dans VS Code, un clic ouvre les fichiers dont le type est géré par getout dans leur application Windows, et les autres dans VS Code.
