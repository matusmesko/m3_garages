CREATE TABLE IF NOT EXISTS `m3_garage_vehicles` (
    `id`             INT          NOT NULL AUTO_INCREMENT,
    `plate`          VARCHAR(12)  NOT NULL,
    `vin`            VARCHAR(20)  DEFAULT NULL,
    `model`          BIGINT       NOT NULL,
    `vtype`          VARCHAR(20)  NOT NULL DEFAULT 'automobile',
    `owner`          INT          DEFAULT NULL,
    `ownername`      VARCHAR(64)  DEFAULT NULL,
    `groupname`      VARCHAR(50)  DEFAULT NULL,
    `garage`         VARCHAR(50)  NOT NULL DEFAULT 'main',
    `stored`         TINYINT(1)   NOT NULL DEFAULT 1,
    `impound`        TINYINT(1)   NOT NULL DEFAULT 0,
    `props`          LONGTEXT     DEFAULT NULL,
    `use_grade`      INT          DEFAULT NULL,
    `transfer_grade` INT          DEFAULT NULL,
    `created`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `plate` (`plate`),
    UNIQUE KEY `vin` (`vin`),
    KEY `owner` (`owner`),
    KEY `groupname` (`groupname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


