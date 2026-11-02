-- A tiny TDB world dump with its locale tables (tests/pipeline/test_questie_l10n.py)
CREATE TABLE `creature_template_locale` (
  `entry` int unsigned NOT NULL DEFAULT '0',
  `locale` varchar(4) NOT NULL,
  `Name` text,
  `NameAlt` text,
  `Title` text,
  `TitleAlt` text,
  `VerifiedBuild` int DEFAULT '0',
  PRIMARY KEY (`entry`,`locale`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `creature_template_locale` VALUES (240,'deDE','Marschall Dughan',NULL,'Marschall',NULL,61000),(240,'esMX','Alguacil Dughan',NULL,'Alguacil',NULL,61000),(240,'esES','Mariscal Dughan',NULL,NULL,NULL,61000),(240,'itIT','Maresciallo Dughan',NULL,NULL,NULL,61000);
CREATE TABLE `gameobject_template_locale` (
  `entry` int unsigned NOT NULL DEFAULT '0',
  `locale` varchar(4) NOT NULL,
  `name` text,
  `castBarCaption` text,
  `unk1` text,
  `VerifiedBuild` int DEFAULT '0',
  PRIMARY KEY (`entry`,`locale`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `gameobject_template_locale` VALUES (1734,'frFR','Avis de recherche',NULL,NULL,61000);
CREATE TABLE `quest_template_locale` (
  `ID` int unsigned NOT NULL DEFAULT '0',
  `locale` varchar(4) NOT NULL,
  `LogTitle` text,
  `LogDescription` text,
  `QuestDescription` text,
  `AreaDescription` text,
  `PortraitGiverText` text,
  `PortraitGiverName` text,
  `PortraitTurnInText` text,
  `PortraitTurnInName` text,
  `QuestCompletionLog` text,
  `VerifiedBuild` int DEFAULT '0',
  PRIMARY KEY (`ID`,`locale`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `quest_template_locale` VALUES (176,'koKR','현상 수배: 들창코 호그','거대한 놀 발톱을 가져가십시오.','호그가 너무 오래 날뛰었습니다.',NULL,NULL,NULL,NULL,NULL,NULL,61000);
CREATE TABLE `quest_offer_reward_locale` (
  `ID` int unsigned NOT NULL DEFAULT '0',
  `locale` varchar(4) NOT NULL,
  `RewardText` text,
  `VerifiedBuild` int DEFAULT '0',
  PRIMARY KEY (`ID`,`locale`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `quest_offer_reward_locale` VALUES (176,'koKR','잘했습니다.',61000);
CREATE TABLE `quest_request_items_locale` (
  `ID` int unsigned NOT NULL DEFAULT '0',
  `locale` varchar(4) NOT NULL,
  `CompletionText` text,
  `VerifiedBuild` int DEFAULT '0',
  PRIMARY KEY (`ID`,`locale`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `quest_request_items_locale` VALUES (176,'koKR','발톱은 가져왔습니까?',61000);
-- the English of the long quest texts (Forever's Asian languages take a text only where it is ours)
CREATE TABLE `quest_template` (
  `ID` int unsigned NOT NULL DEFAULT '0',
  `QuestType` tinyint unsigned NOT NULL DEFAULT '2',
  `LogTitle` text,
  `LogDescription` text,
  `QuestDescription` text,
  `VerifiedBuild` int DEFAULT '0',
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `quest_template` VALUES (176,2,'Wanted: \"Hogger\"','Bring Huge Gnoll Claw to Marshal Dughan in Goldshire.','Hogger has terrorised  the farms of Elwynn long enough.',61000),(62,2,'The Fargodeep Mine','Explore the mine.','A retail text.',61000);
CREATE TABLE `quest_offer_reward` (
  `ID` int unsigned NOT NULL DEFAULT '0',
  `RewardText` text,
  `VerifiedBuild` int DEFAULT '0',
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `quest_offer_reward` VALUES (176,'You have done Elwynn a great service, $n.',61000);
CREATE TABLE `quest_request_items` (
  `ID` int unsigned NOT NULL DEFAULT '0',
  `CompletionText` text,
  `VerifiedBuild` int DEFAULT '0',
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO `quest_request_items` VALUES (176,'Have you the claw?',61000);
INSERT INTO `quest_template_locale` VALUES (176,'zhTW','懸賞：霍格','把巨型豺狼人爪子交給閃金鎮的杜漢元帥。','霍格在艾爾文森林肆虐太久了。',NULL,NULL,NULL,NULL,NULL,NULL,61000);
INSERT INTO `quest_offer_reward_locale` VALUES (176,'zhTW','你為艾爾文立了大功。',61000);
-- the Latin languages: French typography to Latin-1, Spanish from esMX where esES has none, German
-- loses to CMaNGOS
INSERT INTO `quest_template_locale` VALUES (176,'frFR','Avis de recherche : Lardeur','Apportez la griffe de gnoll énorme au maréchal Dughan à Comté-de-l’Or.','Lardeur terrorise les fermes d’Elwynn depuis trop longtemps… œuvrez !',NULL,NULL,NULL,NULL,NULL,NULL,61000),(176,'esMX','Se busca: Hogger','Lleva la garra de gnoll enorme al alguacil Dughan en Villadorada.','Hogger ha aterrorizado las granjas de Elwynn demasiado tiempo.',NULL,NULL,NULL,NULL,NULL,NULL,61000),(176,'deDE','Gesucht: Hogger','TDB-Ziele.','TDB-Text.',NULL,NULL,NULL,NULL,NULL,NULL,61000);
