USE [LOCAL_DB_NAME]  
      GO  
      DECLARE @linkedserver NVARCHAR(100)= '[LINKEDSERVERNAME]', @dbname NVARCHAR(100)= '[DB_NAME]', @lndb NVARCHAR(100);
SET @lndb = IIF(@linkedserver IS NULL, '', @linkedserver + '.') + @dbname + '.';
WITH cte(lvl,            
         object_id,
         name)
     AS (SELECT 1,
                object_id,
                name
         FROM sys.tables
         WHERE type_desc = 'USER_TABLE'
               AND is_ms_shipped = 0
         UNION ALL
         SELECT cte.lvl + 1,
                t.object_id,
                t.name
         FROM cte
              JOIN sys.tables AS t ON EXISTS
         (
             SELECT NULL
             FROM sys.foreign_keys AS fk
             WHERE fk.parent_object_id = t.object_id
                   AND fk.referenced_object_id = cte.object_id
         )
                                      AND t.object_id <> cte.object_id
                                      AND cte.lvl < 30
         WHERE t.type_desc = 'USER_TABLE'
               AND t.is_ms_shipped = 0),
     level                      --this dependency level 
     AS (SELECT name,
                MAX(lvl) AS dependency_level
         FROM cte
         GROUP BY name)
,
cte_pk                            -- this tables have a primary key
as
(
                 SELECT Col.Column_Name,col.TABLE_NAME
                 FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS Tab,
                      INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE Col
                 WHERE Col.Constraint_Name = Tab.Constraint_Name
                       AND Col.Table_Name = Tab.Table_Name
                       AND Constraint_Type = 'PRIMARY KEY'
   )
,cte_identity
as

(SELECT 
  [schema] = s.name,
  [table] = t.name
FROM sys.schemas AS s
INNER JOIN sys.tables AS t
  ON s.[schema_id] = t.[schema_id]
WHERE EXISTS 
(
  SELECT 1 FROM sys.identity_columns
    WHERE [object_id] = t.[object_id]
)
)



     SELECT table_name
 
,'/*------'+ cast(row_number() over (order by  (select 1)) as nvarchar(10))+'------*/'
 
+iif(exists(select 1 from cte_identity where [table]=table_name),'SET IDENTITY_INSERT '+ table_schema + '.' + TABLE_NAME + ' ON;','')  +
            'MERGE INTO ' + table_schema + '.' + TABLE_NAME + ' AS TGT USING ' + @lndb + table_schema + '.' + TABLE_NAME + ' AS SRC ON ' +
     (
         SELECT STUFF(
         (
             SELECT CAST(IIF(                --in this iif  check primary key columns count in table if more one i need use statemnt 'and'
             (
                 SELECT COUNT(*)
                 FROM cte_pk where
                    Table_Name = Tabb.Table_Name
             ) = 1, ' ', ' and ') AS VARCHAR(MAX)) + 'src.' + COLUMN_NAME + '= tgt.' + COLUMN_NAME
             FROM INFORMATION_SCHEMA.columns clm
             WHERE TABLE_NAME = tabb.TABLE_NAME
                   AND EXISTS
             (
                 SELECT 1
                 FROM cte_pk where Column_Name=clm.COLUMN_NAME
                       AND Table_Name = clm.TABLE_NAME
             ) 
FOR XML PATH('')
         ), 1, IIF(
         (
             SELECT COUNT(*)
                 FROM cte_pk where
                    Table_Name = Tabb.Table_Name
         ) = 1, 1, 4), '')                   --in this iif  check primary key columns count in table if more one we need use xml path symbol count =4
     ) + ' WHEN MATCHED AND EXISTS( SELECT SRC.* EXCEPT SELECT TGT.* )     
THEN   UPDATE     SET ' +      -- in this case check updated data and choosing columns of table without primary key
     (
         SELECT STUFF(
         (
             SELECT CAST(',' AS VARCHAR(MAX)) + 'tgt.' + COLUMN_NAME + '= src.' + COLUMN_NAME
             FROM INFORMATION_SCHEMA.columns clm
             WHERE TABLE_NAME = tabb.TABLE_NAME
                   AND NOT EXISTS
             (
                 SELECT 1
                 FROM cte_pk where Column_Name=clm.COLUMN_NAME
                       AND Table_Name = clm.TABLE_NAME
             ) FOR XML PATH('')
         ), 1, 1, '')
     ) + ' WHEN
NOT MATCHED THEN  INSERT (' +             --in this case for insert.
     (
         SELECT STUFF(
         (
             SELECT CAST(',' AS VARCHAR(MAX)) + COLUMN_NAME
             FROM INFORMATION_SCHEMA.columns clm
             WHERE TABLE_NAME = tabb.TABLE_NAME 
         --AND NOT EXISTS                        -- this case depend on you target server. If target server tables primary key have a default data (identity, new_id()) you need use this condition.
            -- (
            --     SELECT 1
            --     FROM cte_pk where Column_Name=clm.COLUMN_NAME
            --           AND Table_Name = clm.TABLE_NAME
            -- ) 
FOR XML PATH('')
         ), 1, 1, '')
     ) + ') VALUES (' +
     (
         SELECT STUFF(
         (
             SELECT CAST(',' AS VARCHAR(MAX)) + 'src.' + COLUMN_NAME
             FROM INFORMATION_SCHEMA.columns clm
             WHERE TABLE_NAME = tabb.TABLE_NAME
          --AND NOT EXISTS                        -- this case depend on you target server. If target server tables primary key have a default data (identity, new_id()) you need use this condition.
            -- (
            --     SELECT 1
            --     FROM cte_pk where Column_Name=clm.COLUMN_NAME
            --           AND Table_Name = clm.TABLE_NAME
            -- ) 
  FOR XML PATH('')
         ), 1, 1, '')
     ) + ')
WHEN NOT MATCHED BY SOURCE THEN   DELETE 
;' +-- in this case for delete data. If don't need delete add here comment
iif(exists(select 1 from cte_identity where [table]=table_name),'SET IDENTITY_INSERT '+ table_schema + '.' + TABLE_NAME + ' OFF;','')  ide
     FROM INFORMATION_SCHEMA.TABLES tabb
          JOIN level ON tabb.TABLE_NAME = level.name
     WHERE TABLE_TYPE = 'BASE TABLE' --and TABLE_SCHEMA in ('rel','list')
and EXISTS(select 1 from cte_pk where TABLE_NAME=tabb.TABLE_NAME)
     ORDER BY level.dependency_level;
