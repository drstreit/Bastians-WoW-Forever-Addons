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
