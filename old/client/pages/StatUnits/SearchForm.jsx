import React, { useState, useEffect } from 'react'
import { bool, func, number, oneOfType, shape, string, objectOf } from 'prop-types'
import { Button, Form, Segment, Checkbox, Grid, Message } from 'semantic-ui-react'

import { confirmHasOnlySortRule, confirmIsEmpty } from 'helpers/validation.js'
import { DateTimeField, SelectField } from '/components/fields'
import { canRead } from 'helpers/config.js'
import { statUnitTypes, statUnitSearchOptions } from 'helpers/enums.js'
import { isDatesCorrect } from 'helpers/dateHelper.js'
import styles from './styles.scss'

const types = [['any', 'AnyType'], ...statUnitTypes]

function SearchForm({
  formData: initialFormData,
  onChange,
  onSubmit,
  onReset,
  setSearchCondition,
  errors,
  localize,
  extended,
  disabled,
  locale,
}) {
  const [formData, setFormData] = useState(initialFormData)
  const [extendedData, setExtendedData] = useState(extended)

  const onSearchModeToggle = () => {
    setExtendedData(prevExtended => !prevExtended)
  }

  useEffect(() => {
    setFormData(initialFormData)
  }, [initialFormData])

  useEffect(() => {
    // Set Enterprise unit as default on form load
    handleChange('type', 3)
  }, [])

  useEffect(() => {
    if (
      (formData.turnoverTo || formData.turnoverFrom) &&
      (formData.employeesNumberTo || formData.employeesNumberFrom)
    ) {
      if (!formData.comparison) {
        setSearchCondition('2')
      }
    }
  }, [formData, setSearchCondition])

  const handleChange = (name, value) => {
    onChange(name, name === 'type' && value === 'any' ? undefined : value)
  }

  const handleReset = () => {
    onReset()
  }

  const handleChangeCheckbox = (name, checked) => {
    onChange(name, checked)
  }

  const handleSelectField = name => (_, { value }) => {
    onChange(name, value === 0 ? undefined : value)
  }

  const typeOptions = types.map(kv => ({
    value: kv[0],
    text: localize(kv[1]),
  }))

  const type = typeOptions[Number(formData.type) || 0].value

  const includeLiquidated =
    formData.includeLiquidated && formData.includeLiquidated.toString().toLowerCase() === 'true'

  const localizedOptions = statUnitSearchOptions.map(x => ({
    ...x,
    text: localize(x.text),
  }))

  const noneConditionIsDisabled = !!(
    (formData.employeesNumberFrom || formData.employeesNumberTo) &&
    (formData.turnoverFrom || formData.turnoverTo)
  )

  const datesCorrect = isDatesCorrect(formData.lastChangeFrom, formData.lastChangeTo)

  return (
    <Form onSubmit={onSubmit} className={styles.searchForm} loading={disabled} error>
      <Segment>
        <Grid divided columns="equal">
          <Grid.Row stretched>
            <Grid.Column>
              <Form.Input
                name="name"
                value={formData.name || ''}
                onChange={(e, { name, value }) => handleChange(name, value)}
                label={localize('SearchWildcard')}
                placeholder={localize('SearchWildcard')}
                size="large"
              />
            </Grid.Column>

            <Grid.Column>
              <label className={styles.label} htmlFor="sort">
                {localize('Sort')}
              </label>

              <Form.Group className={styles.groupStyle}>
                <Form.Field className={styles.selectStyle}>
                  <Form.Select
                    name="sortBy"
                    value={formData.sortBy || null}
                    options={localizedOptions}
                    selection
                    onChange={(e, { name, value }) => handleChange(name, value)}
                    placeholder={localize('SelectSortBy')}
                  />
                  <div className={styles.radio}>
                    <Checkbox
                      radio
                      label={localize('ASC')}
                      name="sortRule"
                      value={1}
                      checked={formData.sortRule === 1 && formData.sortBy !== undefined}
                      onChange={(e, { name, value }) => handleChange(name, value)}
                      disabled={formData.sortBy === undefined}
                    />
                    <Checkbox
                      radio
                      label={localize('DESC')}
                      name="sortRule"
                      value={2}
                      checked={formData.sortRule === 2 && formData.sortBy !== undefined}
                      onChange={(e, { name, value }) => handleChange(name, value)}
                      disabled={formData.sortBy === undefined}
                    />
                  </div>
                </Form.Field>
              </Form.Group>
            </Grid.Column>
            <Grid.Column>
              <Form.Select
                name="type"
                value={type}
                onChange={(e, { name, value }) => handleChange(name, value)}
                options={typeOptions}
                label={localize('StatisticalUnitType')}
                size="large"
                search
              />
            </Grid.Column>
          </Grid.Row>
        </Grid>
      </Segment>
      <div className={styles.extendedTaskbar}>
        <Button
          content={localize('Search')}
          icon="search"
          labelPosition="left"
          type="submit"
          floated="right"
          primary
        />
        <Button
          onClick={onSearchModeToggle}
          content={localize(extendedData ? 'SearchDefault' : 'SearchExtended')}
          icon={extendedData ? 'angle double up' : 'angle double down'}
          labelPosition="left"
          type="button"
          floated="right"
        />
        <Button
          onClick={handleReset}
          content={localize('Reset')}
          disabled={confirmIsEmpty(formData) || confirmHasOnlySortRule(formData)}
          icon="undo"
          labelPosition="left"
          type="button"
          floated="right"
          primary
        />
      </div>

      {extendedData && (
        <div>
          <Segment>
            <Grid divided columns="equal">
              <Grid.Row stretched>
                <Grid.Column>
                  <Form.Input
                    name="statId"
                    value={formData.statId || ''}
                    onChange={(e, { name, value }) => handleChange(name, value)}
                    label={localize('StatId')}
                  />
                  {canRead('TaxRegId') && (
                    <Form.Input
                      name="taxRegId"
                      value={formData.taxRegId || ''}
                      onChange={(e, { name, value }) => handleChange(name, value)}
                      label={localize('TaxRegId')}
                    />
                  )}
                </Grid.Column>
                <Grid.Column>
                  {canRead('ExternalId') && (
                    <Form.Input
                      name="externalId"
                      value={formData.externalId || ''}
                      onChange={(e, { name, value }) => handleChange(name, value)}
                      label={localize('ExternalId')}
                    />
                  )}
                  {canRead('Address') && (
                    <Form.Input
                      name="address"
                      value={formData.address || ''}
                      onChange={(e, { name, value }) => handleChange(name, value)}
                      label={localize('Address')}
                    />
                  )}
                </Grid.Column>
              </Grid.Row>
            </Grid>
          </Segment>
          <Segment>
            <Grid divided columns="equal">
              <Grid.Row>
                <Grid.Column>
                  {canRead('Turnover') && (
                    <Form.Input
                      name="turnoverFrom"
                      value={formData.turnoverFrom || ''}
                      onChange={(e, { name, value }) => handleChange(name, value)}
                      label={localize('TurnoverFrom')}
                      type="number"
                      min={0}
                    />
                  )}
                  {canRead('Turnover') && (
                    <Form.Input
                      name="turnoverTo"
                      value={formData.turnoverTo || ''}
                      onChange={(e, { name, value }) => handleChange(name, value)}
                      label={localize('TurnoverTo')}
                      type="number"
                      min={0}
                    />
                  )}
                  {errors && errors.turnoverError && (
                    <Message size="small" error content={errors.turnoverError} />
                  )}
                </Grid.Column>
                <Grid.Column width={2} className={styles.toggle}>
                  <label className={styles.label} htmlFor="condition">
                    {localize('Condition')}
                  </label>
                  <fieldset id="condition" className={styles.fieldset}>
                    <Form.Group>
                      <Form.Field>
                        <Checkbox
                          radio
                          label={localize('None')}
                          name="comparison"
                          value={undefined}
                          checked={formData.comparison === undefined}
                          onChange={(e, { name, value }) => handleChange(name, value)}
                          disabled={noneConditionIsDisabled}
                        />
                        <br />
                        <br />
                        <Checkbox
                          radio
                          label={localize('AND')}
                          name="comparison"
                          value="1"
                          checked={formData.comparison === '1'}
                          onChange={(e, { name, value }) => handleChange(name, value)}
                        />
                        <br />
                        <br />
                        <Checkbox
                          radio
                          label={localize('OR')}
                          name="comparison"
                          value="2"
                          checked={formData.comparison === '2'}
                          onChange={(e, { name, value }) => handleChange(name, value)}
                        />
                      </Form.Field>
                    </Form.Group>
                  </fieldset>
                </Grid.Column>
                <Grid.Column>
                  {canRead('Employees') && (
                    <Form.Input
                      name="employeesNumberFrom"
                      value={formData.employeesNumberFrom || ''}
                      onChange={(e, { name, value }) => handleChange(name, value)}
                      label={localize('NumberOfEmployeesFrom')}
                      type="number"
                      min={0}
                    />
                  )}
                  {canRead('Employees') && (
                    <Form.Input
                      name="employeesNumberTo"
                      value={formData.employeesNumberTo || ''}
                      onChange={(e, { name, value }) => handleChange(name, value)}
                      label={localize('NumberOfEmployeesTo')}
                      type="number"
                      min={0}
                    />
                  )}
                  {errors && errors.employeesNumberError && (
                    <Message size="small" error content={errors.employeesNumberError} />
                  )}
                </Grid.Column>
              </Grid.Row>
            </Grid>
          </Segment>
          <Form.Group widths="equal">
            <DateTimeField
              name="lastChangeFrom"
              value={formData.lastChangeFrom || ''}
              onChange={(e, { name, value }) => handleChange(name, value)}
              label="DateOfLastChangeFrom"
              localize={localize}
            />
            <DateTimeField
              name="lastChangeTo"
              value={formData.lastChangeTo || ''}
              onChange={(e, { name, value }) => handleChange(name, value)}
              label="DateOfLastChangeTo"
              localize={localize}
              error={!datesCorrect}
              errors={
                datesCorrect
                  ? []
                  : [
                      `"${localize('DateOfLastChangeTo')}" ${localize('CantBeLessThan')} "${localize('DateOfLastChangeFrom')}"`,
                    ]
              }
            />
          </Form.Group>
          <Form.Group widths="equal">
            {canRead('DataSourceClassificationId') && (
              <SelectField
                name="dataSource"
                label="DataSource"
                lookup={7}
                onChange={handleSelectField('dataSourceClassificationId')}
                value={formData.dataSourceClassificationId}
                localize={localize}
                locale={locale}
              />
            )}
            <div className="field">
              <br />
              <Form.Checkbox
                name="includeLiquidated"
                checked={includeLiquidated}
                onChange={(e, { name, checked }) => handleChangeCheckbox(name, checked)}
                label={localize('Includeliquidated')}
              />
            </div>
          </Form.Group>
          <SelectField
            name="regMainActivityIdSearch"
            label="ActualMainActivity1"
            lookup={13}
            onChange={handleSelectField('regMainActivityId')}
            value={formData.regMainActivityId}
            localize={localize}
            locale={locale}
          />
          <SelectField
            name="sectorCodeIdSearch"
            label="InstSectorCode"
            lookup={6}
            onChange={handleSelectField('sectorCodeId')}
            value={formData.sectorCodeId}
            localize={localize}
            locale={locale}
          />
          <SelectField
            name="legalFormIdSearch"
            label="LegalForm"
            lookup={5}
            onChange={handleSelectField('legalFormId')}
            value={formData.legalFormId}
            localize={localize}
            locale={locale}
          />
          <SelectField
            name="regionId"
            label="Region"
            lookup={12}
            onChange={handleSelectField('regionId')}
            value={formData.regionId}
            localize={localize}
            locale={locale}
          />
          <br />
        </div>
      )}
    </Form>
  )
}

SearchForm.propTypes = {
  formData: shape({
    wildcard: string,
    type: oneOfType([number, string]),
    statId: string,
    taxRegId: string,
    externalId: string,
    address: string,
    includeLiquidated: oneOfType([bool, string]),
    turnoverFrom: string,
    turnoverTo: string,
    employeesNumberFrom: string,
    employeesNumberTo: string,
    lastChangeFrom: string,
    lastChangeTo: string,
    dataSource: string,
    regMainActivityId: oneOfType([number, string]),
    sectorCodeId: oneOfType([number, string]),
    legalFormId: oneOfType([number, string]),
    comparison: oneOfType([number, string]),
    sortBy: oneOfType([number, string]),
    sortRule: oneOfType([number, string]),
    regionId: oneOfType([number, string]),
    dataSourceClassificationId: oneOfType([number, string]),
  }),
  onChange: func.isRequired,
  onSubmit: func.isRequired,
  onReset: func.isRequired,
  setSearchCondition: func.isRequired,
  errors: objectOf(string),
  localize: func.isRequired,
  extended: bool,
  disabled: bool,
  locale: string.isRequired,
}

SearchForm.defaultProps = {
  formData: {
    wildcard: '',
    type: 0,
    statId: '',
    taxRegId: '',
    externalId: '',
    address: '',
    includeLiquidated: false,
    turnoverFrom: '',
    turnoverTo: '',
    employeesNumberFrom: '',
    employeesNumberTo: '',
    lastChangeFrom: '',
    lastChangeTo: '',
    regMainActivityId: '',
    sectorCodeId: '',
    legalFormId: '',
    comparison: '',
    sortBy: undefined,
    sortRule: 1,
    regionId: 0,
    dataSourceClassificationId: 0,
  },
  extended: false,
  disabled: false,
}

export default SearchForm
