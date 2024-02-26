import {DrillDownPoint} from "@/app/reports/types/drill-down";
import {useEffect, useRef} from "react";
import type {Chart} from "highcharts";
import {chart} from "highcharts";




    




interface DrillDownChartProps {
    readonly points: DrillDownPoint[];
    readonly onSelect: (p: DrillDownPoint) => void;
}

export const DrillDownChart = ({points, onSelect}: DrillDownChartProps) => {
    const _ref = useRef<HTMLDivElement>(null)
    const _chart = useRef<Chart | null>(null)

    useEffect(() => {
        _chart.current?.destroy();

        if (_ref.current) {
            _chart.current = chart({
                chart: {



                    renderTo: _ref.current,
                    events: {
                        //title:{ text: e.point.name},
                        drilldown: (e) => onSelect(e.point.options.custom as DrillDownPoint)
                    },
                    backgroundColor: 'rgb(249, 250, 251)',
                   
                },


                plotOptions: {

                         

                    series: {
                        borderWidth: 0,
                        //pointPadding: 0,
                        groupPadding: 0.07,

                        

                       
                        dataLabels: {
                            enabled: true, // litt rotete
                            shadow:false,
                            inside: false,
                            format: '{point.y}', //ok if pie
                            useHTML: true,

                       
                             //format:'{y}erik',
                           // style: {
                             //   fontWeight: 'normal',
                             //   shadow:false,
                             //   color :'Darkred',
                            //},
                        } //datalabels
                        





                    }
                },

            
                drilldown: {
                    activeAxisLabelStyle: {
                        color: 'Black',//'#12A9DB'
                        fontWeight: 'normal',
                        shadow:false,
                        textDecoration: 'none',
                      },
                      activeDataLabelStyle: {
                        color: '#00719c',
                        textDecoration: 'none',
                      },
                },





                title: {
                    text: 'Number of units', //Num of variable or in y axis' //+ e.point.name
                    style:  {
                        fontSize: '12px' ,
                        fontWeight: 'normal',
                             }
                         },


                xAxis: {
                    //enabled: true,
                    visible:true,
                    lineWidth:0,
                    

                    type: 'category',
                   // style: {
                    //    color: 'red', //no response when drilldown
                    //},
                    //labels: {
                    //    style:   {
                      //      color: 'Darkred'
                        //         }
                        //     }




                },

                yAxis: {
                    visible: false, //true,
                    //lineWidth:1,
                    title: {
                        text: 'number of units variable tbc /turnover / employees'
                    },

                    labels: {
                        style:   {
                            color: 'Black'
                                 }
                             }
                     },


     

               
               

                  
	             tooltip: {  	
                    shared: true,
                    useHTML: true,
                    valueDecimals: 0,
                    backgroundColor: "rgba(255,255,255,0)",
                    backgroundColor: "white", //this is ok else transparent
                    borderRadius: 3,
                    outside: true,
                    style: {
                        fontSize: '12px',
                        fontWeight: 'bold',
                        color: '#00719c', //dark blue bars
                        //color: '#0a3622', //ssb color green tooltip text
                      },     
                  
                     formatter: function (tooltip) {
                         return ('<li>' +this.point.name +  ': '+ this.y + '</li>');
                             }


                         }, //tooltip


                series: [
                    {
                      
                        dataSorting: {
                           enabled: false, //sorterer bars according to size number
                            matchByName: true
                        },

                        type: 'bar',
                        showInLegend: false,  
                        //colorByPoint:true,  //enables different color each bar 
                        data: points?.map(toPointOptionObject),

                    },
                    //{
                    // color:'red',
                     //type:'column' ,  
                     //data: points?.map(toPointOptionObject),
                   // }
                   
   



                ]
            });
        }
    }, [points, onSelect]);

    return (
        <div ref={_ref}/>
    )
}




const toPointOptionObject = (point: DrillDownPoint) => ({
    name: point.name,
    y: point.count,
    drilldown: point.has_children ? '1' : '',


  
    //color: '#0a3622', //ssb color green for all
   color: '#00719c', //dark blue bars
    
        
    custom: point
})

