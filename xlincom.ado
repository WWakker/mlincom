*! 1.2.5                12nov2020
*! Wouter Wakker        wouter.wakker@outlook.com

* 1.2.5     12nov2020   ereturn post, noclear used for xtreg,fe with repost option
* 1.2.4     09nov2020   repost option added
* 1.2.3     07nov2020   estadd option added
* 1.2.2     03nov2020   eform option similar to lincom
* 1.2.1     02nov2020   display options allowed
* 1.2.0     02nov2020   no parentheses necessary and no constrained syntax for single equation
* 1.1.2     26oct2020   up to two decimals in level option allowed
* 1.1.1     21oct2020   allow eqno:coef syntax
* 1.1.0     08jul2020   name specification syntax change (name) --> name=
* 1.0.4     30jun2020   aesthetic changes
* 1.0.3     26jun2020   name change mlincom --> xlincom
* 1.0.2     09jun2020   proper error code when parentheses found in equation
* 1.0.1     07may2020   if statements for display options run slightly faster
* 1.0.0     05may2020   born

program xlincom, eclass
	version 8

	if replay() {
		if "`e(cmd)'" != "xlincom" error 301
		
		syntax [, EForm          ///
		          OR             ///
		          HR             ///
		          SHR            ///
		          IRr            ///
		          RRr            ///
		          Level(cilevel) ///
		          *              ///
		          ]
		
		// Only one display option allowed
		local eformopt : word count `eform' `or' `hr' `shr' `irr' `rrr' 
		if `eformopt' > 1 {
				di as error "only one display option can be specified"
				exit 198
		}
		
		// Get additional display options
		_get_diopts displayopts, `options'

	}
	else {
		syntax anything(equalok id="expression") [, EForm                ///
		                                            OR                   ///
		                                            HR                   ///
		                                            SHR                  ///
		                                            IRr                  ///
		                                            RRr                  ///
		                                            Level(cilevel)       ///
		                                            DF(numlist max=1 >0) ///
		                                            POST                 ///
		                                            REPOST               ///
		                                            COVZERO              ///
		                                            noHEADer             ///
		                                            ESTADD(string asis)  ///
		                                            *                    ///
		                                            ]
		
		// Only one display option allowed
		local eformopt : word count `eform' `or' `hr' `shr' `irr' `rrr' 
		if `eformopt' > 1 {
				di as error "only one display option can be specified"
				exit 198
		}
		
		// Only post or repost allowed
		if "`post'" != "" & "`repost'" != "" {
			di as error "options {bf:post} and {bf:repost} not allowed together"
			exit 198
		}
		
		// Get additional display options
		_get_diopts displayopts, `options'
		
		// Estadd only allowed when not posting results
		if `"`estadd'"' != "" & ("`post'" != "" | "`repost'" != "") {
			di as error "option {bf:estadd} not allowed when posting results"
			exit 198
		}
		if `"`estadd'"' != "" xlincom_parse_estadd `estadd'
		
		// Header option
		if "`header'" != "" local dont *
		
		// Parse input, must be within parentheses,
		// return list of "[name=] equation" and number of equations
		xlincom_check_parentheses `anything'
		local name_eq_list "`s(name_eq_list)'"
		local n_lc = s(n_lc)
			
		// Store b and e(V) matrix
		tempname b eV
		mat `b' = e(b)
		mat `eV' = e(V)
		local rownames : rowfullnames `eV'
		local n_eV = rowsof(`eV')
		
		// Extract estimation output (code based on Roger Newson's lincomest.ado)
		local depname = e(depvar)
		tempvar esample
		local obs = e(N)
		if "`df'" == "" local dof = e(df_r)
		else local dof = `df' 
		gen byte `esample' = e(sample)
		
		// Define tempnames and matrices for results
		tempname estimate se variance beta vcov
		if "`repost'" == "" {
			mat def `beta' = J(1, `n_lc', 0)
			mat def `vcov' = J(`n_lc', `n_lc', 0)
		}
		else {
			tempname betarepost vcovrepost
			mat def `betarepost' = J(1, `n_eV' + `n_lc', 0)
			mat def `vcovrepost' = J(`n_eV' + `n_lc', `n_eV' + `n_lc', 0)	
			mat `betarepost'[1,1] = `b'
			mat `vcovrepost'[1,1] = `eV'
		}
		
		`dont' di
		
		// Start execution
		local i 1
		foreach name_eq of local name_eq_list {
			xlincom_parse_name_eq `"`name_eq'"' `i'
			local eq_names "`eq_names' `s(eq_name)'"
			local name "`s(eq_name)'"
			local eq "`s(eq)'"
			
			xlincom_parse_eq_for_test "`eq'" "`post'" "`repost'" "`covzero'" "`n_lc'"
			qui lincom `s(eq_for_test)', level(`level') df(`df')
			
			`dont' di as txt %13s abbrev("`name':",13)  _column(16) as res "`eq' = 0"
			
			// Get estimates and variances
			scalar `estimate' = r(estimate)
			scalar `se' = r(se)
			
			// Calculate transformed se and var if previous command is logistic (from Roger Newson's lincomest.ado)
			if "`e(cmd)'" == "logistic" {
				scalar `se' = `se' / `estimate'
				scalar `estimate' = log(`estimate')
				if `eformopt' == 0 local or "or"
			}
			
			scalar `variance' = `se' * `se'
			
			// Store results in matrices
			if "`repost'" == "" {
				mat `beta'[1, `i'] = `estimate'
				mat `vcov'[`i', `i'] = `variance'
			}
			else {
				mat `betarepost'[1, `i' + `n_eV'] = `estimate'
				mat `vcovrepost'[`i' + `n_eV', `i' + `n_eV'] = `variance'
			}
			
			// Get column vectors for covariance calculations
			if ("`post'" != "" & "`covzero'" == "" & `n_lc' > 1) | ("`repost'" != "" & "`covzero'" == "") {
				xlincom_get_eq_vector `"`eq'"' `"`rownames'"' `n_eV'
				if "`post'" != "" {
					tempname c`i'
					mat `c`i'' = r(eq_vector)
				}
				else {
					tempname c`=`i'+`n_eV''
					mat `c`=`i'+`n_eV''' = r(eq_vector)
				}
			}
			
			local ++i
		}
		
		// Check if coef doesn't exist already
		if "`repost'" != "" {
			foreach eqname of local eq_names {
				if !missing(colnumb(`b', "xlincom:`eqname'")) {
					di as error "{bf:xlincom:`eqname'} exists already"
					exit 198
				}
			}
		}
		
		// Fill VCOV matrix with covariances
		if "`post'" != "" & "`covzero'" == "" & `n_lc' > 1 {
			forval i = 1 / `n_lc' {
				forval j = 1 / `n_lc' {
					if `i' != `j' mat `vcov'[`i',`j'] = `c`i''' * `eV' * `c`j''
				}
			}
		}
		else if "`repost'" != "" & "`covzero'" == "" {
			forval i = 1/`n_eV' {
				tempname c`i'
				mat `c`i'' = J(`n_eV', 1, 0)
				mat `c`i''[`i', 1] = 1
			}
			forval i = 1/`=`n_lc'+`n_eV'' {
				forval j = 1/`=`n_lc'+`n_eV'' {
					if `i' != `j' & (`i' > `n_eV' | `j' > `n_eV') {
						mat `vcovrepost'[`i',`j'] = `c`i''' * `eV' * `c`j''
					}
				}
			}
		}
			
		// Name rows/cols matrices
		if "`repost'" == "" {
			mat rownames `beta' = y1
			mat colnames `beta' = `eq_names'
			mat rownames `vcov' = `eq_names'
			mat colnames `vcov' = `eq_names'
		}
		else {
			local equations: coleq `b', quoted // Thanks to Ben Jann for these two lines
			local equations: subinstr local equations `""_""' `""main""', all word
			forval i = 1/`n_lc' {
				local equations `"`equations' "xlincom""'
			}
			local names: colnames `b'
			local names `names' `eq_names'
			mat rownames `betarepost' = y1
			mat colnames `betarepost' = `names'
			mat coleq `betarepost' = `equations'
			mat rownames `vcovrepost' = `names'
			mat roweq `vcovrepost' = `equations'
			mat colnames `vcovrepost' = `names'
			mat coleq `vcovrepost' = `equations'
		}
	}
	
	// Eform options 
	if "`eform'" == "" {
		if "`or'" != "" local eform "Odds Ratio"
		else if "`hr'" != "" local eform "Haz. Ratio"
		else if "`shr'" != "" local eform "SHR"
		else if "`irr'" != "" local eform "IRR"
		else if "`rrr'" != "" local eform "RRR"
	}
	else local eform "exp(b)"
	
	di
	
	// Display and post results
	if "`post'" != "" {
		ereturn post `beta' `vcov' , depname("`depname'") obs(`obs') dof(`dof') esample(`esample')
		ereturn local cmd "xlincom"
		ereturn local predict "xlincom_p"
		ereturn display, eform(`eform') level(`level') `displayopts'
	}
	else if "`repost'" != "" {
		cap ereturn repost b = `betarepost' V = `vcovrepost', resize
		if !_rc ereturn display, eform(`eform') level(`level') `displayopts'
		else {
			ereturn post `betarepost' `vcovrepost', noclear
			ereturn display, eform(`eform') level(`level') `displayopts'
		}
	}
	else if replay() ereturn display, eform(`eform') level(`level') `displayopts'
	else {
		tempname hold
		nobreak {
			_estimates hold `hold'
			capture noisily break {
				ereturn post `beta' `vcov' , depname("`depname'") obs(`obs') dof(`dof') esample(`esample')
				ereturn local cmd "xlincom"
				ereturn display, eform(`eform') level(`level') `displayopts'
				if `"`estadd'"' != "" {
					tempname rtable
					mat `rtable' = r(table)
				}
			}
			local rc = _rc
			_estimates unhold `hold'
			if `rc' exit `rc'
			if `"`estadd'"' != "" {
				xlincom_parse_estadd `estadd'
				xlincom_estadd "`n_lc'" "`eq_names'" "`rtable'" "`s(star)'" "`s(se)'" "`s(t)'" "`s(p)'" "`s(ci)'" "`s(bfmt)'" ///
				               "`s(sefmt)'" "`s(tfmt)'" "`s(pfmt)'" "`s(cifmt)'" "`s(left)'" "`s(right)'" `"`s(starlevels)'"'
			}
		}
	}
end

// Check if parentheses are properly specified
program xlincom_check_parentheses, sclass
	version 8
	
	local n_lc 0
	gettoken first : 0, parse(" (")
	if `"`first'"' == "(" { 
		while `"`first'"' != "" {
			local ++n_lc
			gettoken first 0 : 0, parse(" (") match(paren)
			local first `first'
			local name_eq_list `"`name_eq_list' `"`first'"'"'
			gettoken first : 0, parse(" (")
			if !inlist(`"`first'"', "(", "") {
				di as error "equation must be contained within parentheses"
				exit 198
			}
		}
	}
	else {
		local name_eq_list `""`0'""'
		local n_lc 1
	}
	
	sreturn local name_eq_list "`name_eq_list'"
	sreturn local n_lc = `n_lc'
end

// Parse name/eq expression
// Return name and equation
program xlincom_parse_name_eq, sclass
	version 8
	args name_eq n
	
	gettoken first eq : name_eq, parse("=")
	if "`first'" != "`name_eq'" {
		if "`first'" != "=" {
			local wc : word count `first'
			if `wc' > 1 {
				di as error "{bf:`first'} invalid name"
				exit 7
			}
			confirm names `first'
			local eq_name `first'
			gettoken equalsign eq : eq, parse("=")
		}
		else local eq_name lc_`n'
	}
	else {
		local eq_name lc_`n'
		local eq `name_eq'
	}
	
	sreturn local eq_name `eq_name'
	sreturn local eq `eq'
end	

// Parse equation, look for multiple equation expressions
// Return equation that is accepted by test
program xlincom_parse_eq_for_test, sclass
	version 8
	args eq post repost covzero n_lc
	
	if ("`post'" != "" & "`covzero'" == "" & `n_lc' > 1) | ("`repost'" != "" & "`covzero'" == "") {
		gettoken first rest : eq , parse("()")
		if `"`first'"' != `"`eq'"' {
			di as error "parentheses not allowed in equation"
			exit 198
		}
	}
	gettoken first rest : eq , parse(":")
	if `"`first'"' == `"`eq'"' local eq_for_test `"`eq'"'
	else {
		tokenize `"`eq'"', parse(":+-/*()")
		local i 1
		local 0
		while "``i''" != "" {
			local `i' = strtrim("``i''")
			if inlist("``i''", "*", "/", "+", "-", "(", ")") local eq_for_test `"`eq_for_test' ``i''"'
			else if "``=`i'+1''" == ":" & !strpos("``i''", "[") local eq_for_test `"`eq_for_test' [``i'']"'
			else if "``=`i'-1''" == ":" local eq_for_test `"`eq_for_test'``i''"'
			else if "``i''" != ":" & !strpos("``=`i'-1''", "[") local eq_for_test `"`eq_for_test' ``i''"'
			else if !strpos("``=`i'-1''", "]") & strpos("``=`i'-1''", "[") local eq_for_test `"`eq_for_test':"'
			local ++i
		}
	}
	
	sreturn local eq_for_test `eq_for_test'
end


// Parse equation when post option is specified
// Return matrix for covariance calculations
program xlincom_get_eq_vector, rclass
	version 8
	args eq rownames n
	
	tempname A
	mat `A' = J(`n',1,0)
	mat rownames `A' = `rownames'
	tokenize `eq', parse("+-*/")
	local 0
	local i 1
	while "``i''" != "" {
		local `i' = strtrim("``i''")
		cap confirm number ``i''
		if _rc {
			if inlist("``i''", "+", "-") {
				if inlist("``=`i'+1''", "-", "+") { 
					di as error "++, --, +-, -+ not allowed"
					exit 198
				}
			}
			else if inlist("``i''", "*", "/") {
				 if inlist("``=`i'+2''", "*", "/") | inlist("``=`i'+3''", "*", "/") { 
					di as error "maximum number of multiplications/divisions per estimate = 1"
					exit 198
				}
			}
			else if rownumb(`A',"``i''") == . {
				di as error "{bf:``i''} not found in matrix e(b)"
				exit 303
			}
			else { // If parameter in e(V)
				if inlist("``=`i'-1''", "+", "-", "") { 
					if inlist("``=`i'+1''", "+", "-", "") {
						if "``=`i'-1''" == "-" {
							if "``=`i'-2''" == "*" {
								if "``=`i'-4''" == "-" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] + ``=`i'-3''
								else mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] - ``=`i'-3''
							}
							else mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] - 1
						}
						else mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] + 1
					}
					else if inlist("``=`i'+1''", "*", "/") {
						if "``=`i'+1''" == "*" {
							if "``=`i'-1''" == "-" {
								if "``=`i'+2''" == "-" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] + ``=`i'+3''
								else if "``=`i'+2''" == "+" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] - ``=`i'+3''
								else mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] - ``=`i'+2''
							}
							else {
								if "``=`i'+2''" == "-" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] - ``=`i'+3''
								else if "``=`i'+2''" == "+" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] + ``=`i'+3''
								else mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] + ``=`i'+2''
							}
						}
						else if "``=`i'+1''" == "/" {
							if "``=`i'-1''" == "-" {
								if "``=`i'+2''" == "-" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] + 1 / ``=`i'+3''
								else if "``=`i'+2''" == "+" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] - 1 / ``=`i'+3''
								else mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] - 1 / ``=`i'+2''
							}
							else {
								if "``=`i'+2''" == "-" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] - 1 / ``=`i'+3''
								else if "``=`i'+2''" == "+" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] + 1 / ``=`i'+3''
								else mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] + 1 / ``=`i'+2''
							}
						}
					}
				}
				else if "``=`i'-1''" == "*" {
					if "``=`i'-3''" == "-" mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] - ``=`i'-2''
					else mat `A'[rownumb(`A',"``i''"),1] = `A'[rownumb(`A',"``i''"),1] + ``=`i'-2''
				}
			}				
		}
		local ++i
	}
	
	return matrix eq_vector = `A'
end

// Parser for estadd option to check of everything is specified properly
program xlincom_parse_estadd, sclass
	version 8
	syntax anything(id="star|nostar") [, SE                      ///
	                                     T                       ///
	                                     P                       ///
	                                     CI                      ///
	                                     FMT(string)             ///
	                                     BFMT(string)            /// 
	                                     SEFMT(string)           /// 
	                                     TFMT(string)            ///
	                                     PFMT(string)            ///
	                                     CIFMT(string)           ///
	                                     PARentheses             ///
	                                     BRAckets                ///
	                                     STARLevels(string asis) ///
	                                     ]
	
	if !inlist("`anything'", "star", "nostar") {
		di as error "{bf:star} or {bf:nostar} must be specified in option {bf:estadd}"
		exit 198
	}
	
	if "`parentheses'" != "" & "`brackets'" != "" {
		di as error "only one option allowed of options: {bf:parentheses}, {bf:brackets}"
		exit 198
	}
	
	if "`fmt'" != "" & ("`bfmt'" != "" | "`sefmt'" != "" | "`tfmt'" != "" | "`pfmt'" != "") {
		di as error "format options wrongly specified"
		exit 198
	}
	
	foreach format in "`fmt'" "`bfmt'" "`sefmt'" "`tfmt'" "`pfmt'" {
		if "`format'" != "" confirm numeric format `format'
	}
	
	if "`fmt'" != "" {
		local bfmt `fmt'
		local sefmt `fmt'
		local tfmt `fmt'
	}
	
	if "`parentheses'" != "" | "`brackets'" != "" {
		if "`parentheses'" != "" {
			local left "("
			local right ")"
		}
		else {
			local left "["
			local right "]"
		}
	}
	
	if `"`starlevels'"' == "" local starlevels "* 0.05 ** 0.01 *** 0.001"
	xlincom_parse_starlevels `"`starlevels'"'
	
	sreturn local star `anything'
	sreturn local se `se'
	sreturn local t `t'
	sreturn local p `p'
	sreturn local ci `ci'
	sreturn local bfmt `bfmt'
	sreturn local sefmt `sefmt'
	sreturn local tfmt `tfmt'
	sreturn local pfmt `pfmt'
	sreturn local cifmt `cifmt'
	sreturn local left `left'
	sreturn local right `right'
	sreturn local starlevels "`s(starl_list)'"
end

// Parser for starlevels suboption of estadd option
// Check if specified properly and return list of sign/pval combinations
program xlincom_parse_starlevels, sclass
	version 8
	args starlevels
	
	local cnt : word count `starlevels'
	if mod(`cnt', 2) != 0 {
		di as error "option {bf:starlevels} wrongly specified"
		exit 198
	}
	
	forval i = 1/`cnt' {
		if mod(`i', 2) == 0 {
			confirm number `:word `i' of `starlevels''
			if `i' >= 4 {
				if `:word `i' of `starlevels'' >= `:word `=`i'-2' of `starlevels'' {
					di as error "pvalues in option {bf:starlevels} must be specified in descending order"
					exit 198
				}
			}
		}
		else {
			cap confirm number `:word `i' of `starlevels''
			if !_rc {
				di as error "{bf:`:word `i' of `starlevels''} found where string expected
				exit 198
			}
		}
	}
	
	forval i = 1(2)`cnt' {
		local starl_list `"`starl_list' `""`:word `i' of `starlevels''" "`:word `=`i'+1' of `starlevels''""'"'
	}

	sreturn local starl_list "`starl_list'"
end

// Add local or scalars of results to e()
program xlincom_estadd, eclass
	version 8
	args n_lc names rtable star se t p ci bfmt sefmt tfmt pfmt cifmt left right starlevels
	
	// Default formatting
	local defaultfmt %4.3f
	if "`star'" == "star" & "`bfmt'" == "" local bfmt `defaultfmt'
	if "`left'" != "" {
		foreach format in sefmt tfmt pfmt cifmt {
			if "``format''" == "" local `format' `defaultfmt'
		}
	}
	
	forval i = 1/`n_lc' {
		if "`left'" == "" {
			if "`ci'" != "" {
				if "`cifmt'" == "" ereturn local p_`:word `i' of `names'' = "`=`rtable'[5, `i']',`=`rtable'[6, `i']'"
				else ereturn local ci_`:word `i' of `names'' = "`:di `cifmt' `rtable'[5, `i']',`:di `cifmt' `rtable'[6, `i']'"
			}
			if "`p'" != "" {
				if "`pfmt'" == "" ereturn scalar p_`:word `i' of `names'' = `rtable'[4, `i']
				else ereturn local p_`:word `i' of `names'' = `:di `pfmt' `rtable'[4, `i']'
			}
			if "`t'" != "" {
				if "`tfmt'" == "" ereturn scalar t_`:word `i' of `names'' = `rtable'[3, `i']
				else ereturn local t_`:word `i' of `names'' = `:di `tfmt' `rtable'[3, `i']'
			}
			if "`se'" != "" {
				if "`sefmt'" == "" ereturn scalar se_`:word `i' of `names'' = `rtable'[2, `i']
				else ereturn local se_`:word `i' of `names'' = `:di `sefmt' `rtable'[2, `i']'
			}
		}
		else {
			if "`ci'" != "" {
				if "`cifmt'" == "" ereturn local p_`:word `i' of `names'' = "`left'" + "`=`rtable'[5, `i']',`=`rtable'[6, `i']'" + "`right'"
				else ereturn local ci_`:word `i' of `names'' = "`left'" + "`:di `cifmt' `rtable'[5, `i']',`:di `cifmt' `rtable'[6, `i']'" + "`right'"
			}
			if "`p'" != "" {
				if "`pfmt'" == "" ereturn local p_`:word `i' of `names'' = "`left'" + "`=`rtable'[4, `i']'" + "`right'"
				else ereturn local p_`:word `i' of `names'' = "`left'" + "`:di `pfmt' `rtable'[4, `i']'" + "`right'"
			}
			if "`t'" != "" {
				if "`tfmt'" == "" ereturn local t_`:word `i' of `names'' = "`left'" + "`=`rtable'[3, `i']'" + "`right'"
				else ereturn local t_`:word `i' of `names'' = "`left'" + "`:di `tfmt' `rtable'[3, `i']'" + "`right'"
			}
			if "`se'" != "" {
				if "`sefmt'" == "" ereturn local se_`:word `i' of `names'' = "`left'" + "`=`rtable'[2, `i']'" + "`right'"
				else ereturn local se_`:word `i' of `names'' = "`left'" + "`:di `sefmt' `rtable'[2, `i']'" + "`right'"
			}
		}
		if "`star'" == "nostar" {
			if "`bfmt'" == "" ereturn scalar b_`:word `i' of `names'' = `rtable'[1, `i']
			else ereturn local b_`:word `i' of `names'' = `:di `bfmt' `rtable'[1, `i']'
		}
		else {
			local addstar
			foreach level of local starlevels {
				local sign `:word 1 of `level''
				if `rtable'[4, `i'] < `:word 2 of `level'' local addstar `sign'
			}
			if "`bfmt'" == "" ereturn local b_`:word `i' of `names'' = "`=`rtable'[1, `i']'`addstar'"
			else ereturn local b_`:word `i' of `names'' = "`:di `bfmt' `rtable'[1, `i']'`addstar'"
		}
	}
end
