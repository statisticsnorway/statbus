DO $$
DECLARE
    parent_id integer;
BEGIN
    INSERT INTO public.relative_period
        (code                         , name_when_query                      , name_when_input                  , scope             , active)
    VALUES
        ('today'                      , 'Today'                              , 'From today and onwards'         , 'input_and_query' , false)   ,
        --
        ('year_curr'                  , 'Current Year'                       , 'Current year and onwards'       , 'input_and_query' , true)   ,
        ('year_prev'                  , 'Previous Year'                      , 'From previous year and onwards' , 'input_and_query' , true)   ,
        ('year_curr_only'             , NULL                                 , 'Current year only'              , 'input'           , false)   ,
        ('year_prev_only'             , NULL                                 , 'Previous year only'             , 'input'           , false)   ,
        --
        ('start_of_week_curr'         , 'Start of Current Week'              , NULL                             , 'query'           , false)  ,
        ('stop_of_week_prev'          , 'End of Previous Week'               , NULL                             , 'query'           , false)  ,
        ('start_of_week_prev'         , 'Start of Previous Week'             , NULL                             , 'query'           , false)  ,
        ('start_of_month_curr'        , 'Start of Current Month'             , NULL                             , 'query'           , false)  ,
        ('stop_of_month_prev'         , 'End of Previous Month'              , NULL                             , 'query'           , false)  ,
        ('start_of_month_prev'        , 'Start of Previous Month'            , NULL                             , 'query'           , false)  ,
        ('start_of_quarter_curr'      , 'Start of Current Quarter'           , NULL                             , 'query'           , false)  ,
        ('stop_of_quarter_prev'       , 'End of Previous Quarter'            , NULL                             , 'query'           , false)  ,
        ('start_of_quarter_prev'      , 'Start of Previous Quarter'          , NULL                             , 'query'           , false)  ,
        ('start_of_semester_curr'     , 'Start of Current Semester'          , NULL                             , 'query'           , false)  ,
        ('stop_of_semester_prev'      , 'End of Previous Semester'           , NULL                             , 'query'           , false)  ,
        ('start_of_semester_prev'     , 'Start of Previous Semester'         , NULL                             , 'query'           , false)  ,
        ('start_of_year_curr'         , 'Start of Current Year'              , NULL                             , 'query'           , true)   ,
        ('stop_of_year_prev'          , 'End of Previous Year'               , NULL                             , 'query'           , true)   ,
        ('start_of_year_prev'         , 'Start of Previous Year'             , NULL                             , 'query'           , true)   ,
        ('start_of_quinquennial_curr' , 'Start of Current Five-Year Period'  , NULL                             , 'query'           , false)  ,
        ('stop_of_quinquennial_prev'  , 'End of Previous Five-Year Period'   , NULL                             , 'query'           , false)  ,
        ('start_of_quinquennial_prev' , 'Start of Previous Five-Year Period' , NULL                             , 'query'           , false)  ,
        ('start_of_decade_curr'       , 'Start of Current Decade'            , NULL                             , 'query'           , false)  ,
        ('stop_of_decade_prev'        , 'End of Previous Decade'             , NULL                             , 'query'           , false)  ,
        ('start_of_decade_prev'       , 'Start of Previous Decade'           , NULL                             , 'query'           , false)
    ;
END $$;