
/****** Object:  UserDefinedFunction [dbo].[HasCountryAsLevel1]    Script Date: 10/16/2020 5:11:27 PM ******/SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




CREATE OR ALTER FUNCTION [dbo].[GetOblastLevel]()  
RETURNS INT
AS   

BEGIN  
  DECLARE @OblastLevel INT = 1;
	DECLARE @HasCountryAsLevel1 BIT;

	SET @HasCountryAsLevel1 = dbo.HasCountryAsLevel1();
	IF @HasCountryAsLevel1 = 1
	BEGIN
		SET @OblastLevel += 1;
	END

  RETURN @OblastLevel;  
END; 
GO
