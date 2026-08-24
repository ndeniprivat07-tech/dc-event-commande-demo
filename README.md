# DC EVENT COMMANDE — démonstration publique

Maquette d'une application de gestion des locations de matériel événementiel
(sonorisation, éclairage, mobilier, structures, vidéo, décoration).

**➡ Essayer l'application : https://ndeniprivat07-tech.github.io/dc-event-commande-demo/**

**➡ APK Android : https://github.com/ndeniprivat07-tech/dc-event-commande-demo/releases/latest**
(télécharger `DC-EVENT-COMMANDE.apk` sur le téléphone et l'ouvrir — l'APK est
reconstruit automatiquement à chaque mise à jour de l'application)

Aucune installation : l'application tourne entièrement dans le navigateur,
hors connexion une fois chargée. Les données restent sur votre appareil
(`localStorage`) — chaque visiteur a son propre bac à sable.

## Ce que montre la démonstration

Chaque profil est protégé par un mot de passe. Pour la démonstration ils sont
rappelés sur l'écran de connexion : `dc-admin`, `dc-manager`, `dc-depot`.
Dans la version livrée au client, ils ne sont affichés nulle part et se
changent depuis l'application.

Trois profils, sélectionnés à l'ouverture :

| Profil | Rôle |
|---|---|
| **ADMIN** | Gère le catalogue, tranche les validations, voit la traçabilité |
| **MANAGER** | Devis, réservations, facturation, encaissements |
| **PRÉPARATEUR** | Sorties de dépôt, départs, contrôle des retours — aucun montant affiché |

Règles de gestion clés :

- **Le stock est un calendrier** : la disponibilité se calcule sur une période,
  pas sur un compteur global. Un devis ne bloque rien ; une réservation retire
  le matériel du parc sur ses dates.
- **Validation ADMIN obligatoire** pour retirer un article, annuler une commande
  ou accorder plus de 10 % de réduction — motif écrit, conservé et traçable.
- **Chaîne financière complète** : remise, escompte, TVA, acompte, caution,
  retenues pour casse et manquants, restitution du solde, facture imprimable.

## Avertissement

Version de démonstration : identité de société, coordonnées, clients et tarifs
sont **fictifs**. Toute ressemblance avec des sociétés réelles serait fortuite.
