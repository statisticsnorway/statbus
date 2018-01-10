---Table with Activity Categories
With ActualStat
	as (Select * From StatisticalUnits where ParentId IS NULL),
ActualStat1 as(Select a.*, a3.Section Sect, l.Code as CodeLegF, a3.Code as ActCode,
	Case 
	When Section = 'A' or Section = 'B' or Section = 'C' or Section = 'D' or Section = 'E' or Section = 'F' or Section Like 'C%' Then 1 Else 2 end GrpIandII,
	Case
	When l.Code = 36 or l.Code = 63 Then 'Farm'
	When l.Code = 60 or l.Code = 61 or l.Code = 62 Then 'Individual'
	When l.Code = 70 or l.Code = 71 or l.Code = 72 Then 'Sublegal Unit' end LForm
	From ActualStat a 
	Join ActivityStatisticalUnits a1 on a.RegId = a1.Unit_Id
	Join Activities a2 on a1.Activity_Id = a2.Id
	Join ActivityCategories a3 on a2.ActivityCategoryId = a3.Id
	Join LegalForms l on a.LegalFormId = l.Id),

ActualStatFinal 
	as(Select *,
	Case
	When GrpIandII = 1 
	Then
		(Case
			When ((NumOfPeopleEmp <= 50 or Turnover < 500) and LForm IS NULL) Then 'Small'
			When (((NumOfPeopleEmp > 50 and NumOfPeopleEmp <= 200) or (Turnover >= 500 and Turnover < 2000)) and LForm IS NULL or Discriminator = 'Enterprise') Then 'Medium'
			When ((NumOfPeopleEmp > 200 or Turnover >= 2000) and LForm IS NULL  or Discriminator = 'Enterprise') Then 'Big' 
			else LForm
			end)
	When GrpIandII = 2 
	Then
		(Case
			When ((NumOfPeopleEmp <= 15 or Turnover < 500) and LForm IS NULL) Then 'Small'
			When (((NumOfPeopleEmp > 16 and NumOfPeopleEmp <= 50) or (Turnover >= 500 and Turnover < 2000)) and LForm IS NULL or Discriminator = 'Enterprise') Then 'Medium'
			When ((NumOfPeopleEmp > 50 or Turnover >= 2000) and LForm IS NULL  or Discriminator = 'Enterprise') Then 'Big'
			else LForm
			end)
	end SizeGrp,
	Case
	When CodeLegF = 12 Then 'Gov'
	When CodeLegF = 14 Then 'Mun'
	When CodeLegF = 60 or CodeLegF = 61 or CodeLegF = 62 or CodeLegF = 63 Then 'Private'
	Else 'Else' end PropGrp,
	IIF(Status = 1, 1, 0) Statuso,
	IIF(Discriminator = 'LegalUnit', 1 , 0) Legal,
	IIF(Discriminator = 'LegalUnit' and Status = 1, 1, 0) ALegal,
	IIF(year(RegIdDate) = year(getdate()), 1, 0) y
	From ActualStat1),

RegionsTree(ChildId, ChildName, ParentId, Parents, Level)
	AS
	(
	SELECT Id, Name, ParentId, CAST('' AS VARCHAR(MAX)), 1
	FROM Regions ---Where ParentId IS NULL
	UNION ALL
	SELECT Childs.Id, Childs.Name, Childs.ParentId,
	CAST(CASE WHEN Parent.Parents = ''
	THEN(CAST(Childs.ParentId AS VARCHAR(MAX)))
	ELSE(Parent.Parents + '.' + CAST(Childs.ParentId AS VARCHAR(MAX)))
	END AS VARCHAR(MAX)), Parent.Level + 1
	FROM Regions AS Childs
	INNER JOIN RegionsTree AS Parent ON Childs.ParentId = Parent.ChildId and Childs.ParentId != Childs.Id
	),

RegionsFinal
	as (Select ChildId, ChildName, Parents, Level From (Select *, Max(Len(Parents)) over(partition by ChildId) maxl From RegionsTree) x Where Len(Parents) = maxl),

ActualStatWithRegions
as (Select s.*, ChildName, Parents, ChildId From ActualStatFinal s 
	Join Address a on a.Address_id = s.ActualAddressId
	Join RegionsFinal r on r.ChildId = a.Region_id),



---NPO2

t1 as (Select ActCode, year(RegIdDate) y, Count(RegId) qty 
	From (
		Select RegId, RegIdDate, ActCode
		From ActualStatFinal
		Where Left(ActCode,2) = '94'
	) x group by ActCode,  year(RegIdDate))

Select Name, [2012] , [2013], [2014], [2015], [2016], [2017] 
	From (
		Select a.Name as Name, y, qty 
		From (
			Select ActCode, y, 
			sum(qty) over(partition by ActCode order by y ROWS UNBOUNDED PRECEDING) qty
			From t1
		) t2 Join ActivityCategories a on t2.ActCode = a.Code Where y > 2011
	)t3 
	Pivot (sum(qty) for y in ([2012] , [2013], [2014], [2015], [2016], [2017])) pvt
