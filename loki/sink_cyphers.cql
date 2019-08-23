>>>SURVEY_JSON
WITH event, apoc.convert.fromJsonMap(event.content) AS c
  MERGE (s:Valhalla_Survey {uid: event.uid, format: event.format})
WITH s, c
  SET s.title = [c['title']['en'], c['title']['fr']], s.description = [c['description']['en'], c['description']['fr']], s.valid = [c['valid']['from'], c['valid']['to']], s.version = c.version
WITH s, c['questions'] AS questions
  UNWIND questions AS cq
WITH s, cq
  FOREACH (dummy IN CASE WHEN cq['qid'] <> 'none' THEN [1] ELSE [] END |
    MERGE (q:Valhalla_Question {uid: cq['cortex']['uid']})
    FOREACH (dummy IN CASE WHEN cq['cortex']['questionType'] = 'SINGLE_CHOICE' THEN [1] ELSE [] END | SET q:SINGLE_CHOICE)
    FOREACH (dummy IN CASE WHEN cq['cortex']['questionType'] = 'MULTI_CHOICE' THEN [1] ELSE [] END | SET q:MULTI_CHOICE)
    FOREACH (dummy IN CASE WHEN cq['cortex']['questionType'] = 'FREE_TEXT' THEN [1] ELSE [] END | SET q:FREE_TEXT)
    SET q.type = cq['cortex']['questionType'], q.question = [cq['question']['en'], cq['question']['fr']], q.classified_as = cq['cortex']['classifiedAs'], q.options = apoc.convert.toJson(cq['options'])
    MERGE (q)<-[:AT_ORDER {n: cq['cortex']['atOrder']}]-(s)
  )
<<<

>>>SURVEY_RESPONSE
WITH event, apoc.convert.fromJsonMap(event.content) AS c
  MERGE (s:Valhalla_Survey {uid: c['response']['conducted']})
    MERGE (r:Valhalla_Response {uid: event.uid})
      MERGE (r)-[:RESPOND_TO]->(s)
WITH r, c, c['respondent'] AS cr
  MERGE (d:Valhalla_Respondent {uid: apoc.create.uuid()})
    FOREACH (dummy IN CASE WHEN cr.fluent_at IS NOT NULL THEN [1] ELSE [] END |
      MERGE (a:GC_Language {uid: TRIM(cr.fluent_at)})
        MERGE (d)-[:FLUENT_AT]->(a))
    FOREACH (dummy IN CASE WHEN cr.located_in IS NOT NULL THEN [1] ELSE [] END |
      MERGE (a:CP_CSD {name: TRIM(SPLIT(cr.located_in, ',')[0])})-[:CSD_IN_PR]->(p:CP_Province {uid: SPLIT(TRIM(SPLIT(cr.located_in, ',')[1]), ' ')[0]})
        MERGE (d)-[:LOCATED_IN]->(a))
    FOREACH (dummy IN CASE WHEN cr.in_department IS NOT NULL THEN [1] ELSE [] END |
      MERGE (a:GC_Org {en_name: TRIM(SPLIT(cr.in_department, '(')[0])})
        MERGE (d)-[:IN_DEPARTMENT]->(a))
    FOREACH (dummy IN CASE WHEN cr.work_as IS NOT NULL THEN [1] ELSE [] END |
      MERGE (a:GC_ClsLvl {uid: TRIM(cr.work_as)})
        MERGE (d)-[:WORK_AS]->(a))
    MERGE (d)-[:RESPONDENT_OF]->(r)
      SET r.created = [c['created']['from'], c['created']['to']]
  WITH r, c, c['questions'] AS questions
    UNWIND questions AS cq
  WITH r, c, cq
    MERGE (q:Valhalla_Question {uid: cq['uid']})
  WITH r, c, cq, q, CASE WHEN q.stats IS NULL THEN apoc.map.fromPairs([]) ELSE apoc.convert.fromJsonMap(q.stats) END AS map
    FOREACH (dummy IN CASE WHEN q.type <> 'CLASSIFIED' THEN [1] ELSE [] END |
      FOREACH (dummy IN CASE WHEN (cq['questionType'] = 'SINGLE_CHOICE' OR cq['questionType'] = 'FREE_TEXT') THEN [1] ELSE [] END |
        MERGE (a:Valhalla_Answer {text: cq['questionAnswer']})
          MERGE (r)-[:AT_ORDER {n: cq['atOrder']}]->(a)
            MERGE (a)-[:ANSWER_OF]->(q)
              SET q.stats = apoc.convert.toJson(apoc.map.setKey(map, cq['questionAnswer'], apoc.map.get(map, cq['questionAnswer'], 0) + 1)),
                  q.answer_total = CASE WHEN q.answer_total IS NULL THEN 1 ELSE q.answer_total + 1 END
      )
      FOREACH (dummy IN CASE WHEN cq['questionType'] = 'MULTI_CHOICE' THEN [1] ELSE [] END |
        FOREACH (answer IN cq['questionAnswer'] |
          MERGE (a:Valhalla_Answer {text: answer})
            MERGE (r)-[:AT_ORDER {n: cq['atOrder']}]->(a)
              MERGE (a)-[:ANSWER_OF]->(q)
                SET q.stats = apoc.convert.toJson(apoc.map.setKey(map, answer, apoc.map.get(map, answer, 0) + 1)),
                    q.answer_total = CASE WHEN q.answer_total IS NULL THEN 1 ELSE q.answer_total + 1 END
        )
      )
    )
    FOREACH (dummy IN CASE WHEN q.classified_as = 'GC_Org' THEN [1] ELSE [] END |
      MERGE (a:GC_Org {en_name: TRIM(SPLIT(cq['questionAnswer'], '(')[0])})
        MERGE (r)-[:AT_ORDER {n: cq['atOrder']}]->(a)
          MERGE (a)-[:ANSWER_OF]->(q)
            SET q.stats = apoc.convert.toJson(apoc.map.setKey(map, a.en_name, apoc.map.get(map, a.en_name, 0) + 1)),
                q.answer_total = CASE WHEN q.answer_total IS NULL THEN 1 ELSE q.answer_total + 1 END
    )
    FOREACH (dummy IN CASE WHEN q.classified_as = 'GC_Language' THEN [1] ELSE [] END |
      MERGE (a:GC_Language {name: TRIM(cq['questionAnswer'])})
        MERGE (r)-[:AT_ORDER {n: cq['atOrder']}]->(a)
          MERGE (a)-[:ANSWER_OF]->(q)
            SET q.stats = apoc.convert.toJson(apoc.map.setKey(map, a.name, apoc.map.get(map, a.name, 0) + 1)),
                q.answer_total = CASE WHEN q.answer_total IS NULL THEN 1 ELSE q.answer_total + 1 END
    )
    FOREACH (dummy IN CASE WHEN q.classified_as = 'GC_ClsLvl' THEN [1] ELSE [] END |
      MERGE (a:GC_ClsLvl {uid: TRIM(cq['questionAnswer'])})
        MERGE (r)-[:AT_ORDER {n: cq['atOrder']}]->(a)
          MERGE (a)-[:ANSWER_OF]->(q)
            SET q.stats = apoc.convert.toJson(apoc.map.setKey(map, a.uid, apoc.map.get(map, a.uid, 0) + 1)),
                q.answer_total = CASE WHEN q.answer_total IS NULL THEN 1 ELSE q.answer_total + 1 END
    )
    FOREACH (dummy IN CASE WHEN q.classified_as = 'CP_CSD' THEN [1] ELSE [] END |
      MERGE (a:CP_CSD {name: TRIM(SPLIT(cq['questionAnswer'], ',')[0])})-[:CSD_IN_PR]->(p:CP_Province {uid: SPLIT(TRIM(SPLIT(cq['questionAnswer'], ',')[1]), ' ')[0]})
        MERGE (r)-[:AT_ORDER {n: cq['atOrder']}]->(a)
          MERGE (a)-[:ANSWER_OF]->(q)
            SET q.stats = apoc.convert.toJson(apoc.map.setKey(map, a.name, apoc.map.get(map, a.name, 0) + 1)),
                q.answer_total = CASE WHEN q.answer_total IS NULL THEN 1 ELSE q.answer_total + 1 END
    )
    WITH r, c, q, apoc.map.fromPairs([['uid', q.uid], ['total', q.answer_total], ['stats', q.stats]]) AS map
        CALL streams.publish('survey_metrics', map)
    WITH DISTINCT(r) AS r, c, REDUCE(m=[], q IN c['questions'] | CASE WHEN q['questionType'] = 'FREE_TEXT' THEN m + [apoc.map.fromPairs([['uid', q['uid']], ['text', q['questionAnswer']]])] ELSE m END) AS data
    WITH apoc.map.fromPairs([['uid', r.uid], ['data', data]]) AS map
        CALL streams.publish('nlp_process', map)
    RETURN 1
<<<