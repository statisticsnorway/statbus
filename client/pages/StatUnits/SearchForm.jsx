import React from 'react'
import { bool, func, number, oneOfType, shape, string } from 'prop-types'
import { Button, Form, Popup, Segment, Checkbox, Grid } from 'semantic-ui-react'

import { DateTimeField, SelectField } from 'components/fields'
import { canRead } from 'helpers/config'
import { statUnitTypes, statUnitSearchOptions } from 'helpers/enums'
import { getDate } from 'helpers/dateHelper'
import styles from './styles.pcss'

const types = [['any', 'AnyType'], ...statUnitTypes]

class SearchForm extends React.Component {
  static propTypes = {
    formData: shape({
      wildcard: string,
      type: oneOfType([number, string]),
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
    localize: func.isRequired,
    extended: bool,
  }

  static defaultProps = {
    formData: {
      wildcard: '',
      type: 0,
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
  }

  state = {
    data: this.props.extended,
  }

  onSearchModeToggle = (e) => {
    e.preventDefault()
    this.setState(s => ({ data: { ...s.data, extended: !s.data.extended } }))
  }

  handleChange = (_, { name, value }) => {
    this.props.onChange(name, name === 'type' && value === 'any' ? undefined : value)
  }

  handleChangeCheckbox = (_, { name, checked }) => {
    this.props.onChange(name, checked)
  }

  handleSelectField = name => (_, { value }) => {
    this.props.onChange(name, value === 0 ? undefined : value)
  }

  render() {
    const { formData, localize, onSubmit } = this.props
    const { extended } = this.state.data
    const isDatesCorrect =
      getDate(formData.lastChangeFrom) > getDate(formData.lastChangeTo) &&
      (formData.lastChangeTo !== undefined || formData.lastChangeTo !== '')

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

    return (
      <Form onSubmit={onSubmit} className={styles.form}>
        <Segment>
          <Grid divided columns="equal">
            <Grid.Row stretched>
              <Grid.Column>
                <Form.Input
                  name="wildcard"
                  value={formData.wildcard}
                  onChange={this.handleChange}
                  label={localize('SearchWildcard')}
                  placeholder={localize('TypeAndPressSearch')}
                  size="large"
                />
              </Grid.Column>

              <Grid.Column>
                <label className={styles.label} htmlFor="sort">
                  {localize('Sort')}
                </label>
                <fieldset id="sort" className={styles.fieldset}>
                  <Form.Group className={styles.groupStyle}>
                    <Form.Field className={styles.selectStyle}>
                      <Form.Select
                        name="sortBy"
                        value={formData.sortBy}
                        options={localizedOptions}
                        selection
                        onChange={this.handleChange}
                        placeholder={localize('SelectSortBy')}
                      />
                      <div className={styles.radio}>
                        <Checkbox
                          radio
                          label={localize('ASC')}
                          name="sortRule"
                          value={1}
                          checked={formData.sortRule === 1 && formData.sortBy !== undefined}
                          onChange={this.handleChange}
                          disabled={formData.sortBy === undefined}
                        />
                        <Checkbox
                          radio
                          label={localize('DESC')}
                          name="sortRule"
                          value={2}
                          checked={formData.sortRule === 2 && formData.sortBy !== undefined}
                          onChange={this.handleChange}
                          disabled={formData.sortBy === undefined}
                        />
                      </div>
                    </Form.Field>
                  </Form.Group>
                </fieldset>
              </Grid.Column>
              <Grid.Column>
                <Form.Select
                  name="type"
                  value={type}
                  onChange={this.handleChange}
                  options={typeOptions}
                  label={localize('StatisticalUnitType')}
                  size="large"
                  search
                />
              </Grid.Column>
            </Grid.Row>
          </Grid>
        </Segment>

        {extended && (
          <div>
            <Segment>
              <Grid divided columns="equal">
                <Grid.Row stretched>
                  <Grid.Column>
                    {canRead('Turnover') && (
                      <Form.Input
                        name="turnoverFrom"
                        value={formData.turnoverFrom}
                        onChange={this.handleChange}
                        label={localize('TurnoverFrom')}
                        type="number"
                        min={0}
                      />
                    )}
                    {canRead('Turnover') && (
                      <Form.Input
                        name="turnoverTo"
                        value={formData.turnoverTo}
                        onChange={this.handleChange}
                        label={localize('TurnoverTo')}
                        type="number"
                        min={0}
                      />
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
                            onChange={this.handleChange}
                          />
                          <br />
                          <br />
                          <Checkbox
                            radio
                            label={localize('AND')}
                            name="comparison"
                            value="1"
                            checked={formData.comparison === '1'}
                            onChange={this.handleChange}
                          />
                          <br />
                          <br />
                          <Checkbox
                            radio
                            label={localize('OR')}
                            name="comparison"
                            value="2"
                            checked={formData.comparison === '2'}
                            onChange={this.handleChange}
                          />
                        </Form.Field>
                      </Form.Group>
                    </fieldset>
                  </Grid.Column>
                  <Grid.Column>
                    {canRead('Employees') && (
                      <Form.Input
                        name="employeesNumberFrom"
                        value={formData.employeesNumberFrom}
                        onChange={this.handleChange}
                        label={localize('NumberOfEmployeesFrom')}
                        type="number"
                        min={0}
                      />
                    )}
                    {canRead('Employees') && (
                      <Form.Input
                        name="employeesNumberTo"
                        value={formData.employeesNumberTo}
                        onChange={this.handleChange}
                        label={localize('NumberOfEmployeesTo')}
                        type="number"
                        min={0}
                      />
                    )}
                  </Grid.Column>
                </Grid.Row>
              </Grid>
            </Segment>
            <Form.Group widths="equal">
              <DateTimeField
                name="lastChangeFrom"
                value={formData.lastChangeFrom || ''}
                onChange={this.handleChange}
                label="DateOfLastChangeFrom"
                localize={localize}
              />
              <Popup
                trigger={
                  <div className={`field ${styles.items}`}>
                    <DateTimeField
                      name="lastChangeTo"
                      value={formData.lastChangeTo || ''}
                      onChange={this.handleChange}
                      label="DateOfLastChangeTo"
                      localize={localize}
                      error={isDatesCorrect}
                    />
                  </div>
                }
                content={`"${localize('DateOfLastChangeTo')}" ${localize('CantBeLessThan')} "${localize('DateOfLastChangeFrom')}"`}
                open={isDatesCorrect}
              />
            </Form.Group>
            <Form.Group widths="equal">
              {canRead('DataSourceClassificationId') && (
                <SelectField
                  name="dataSource"
                  label="DataSource"
                  lookup={7}
                  onChange={this.handleSelectField('dataSourceClassificationId')}
                  value={formData.dataSourceClassificationId}
                  localize={localize}
                />
              )}
              <div className="field">
                <br />
                <Form.Checkbox
                  name="includeLiquidated"
                  checked={includeLiquidated}
                  onChange={this.handleChangeCheckbox}
                  label={localize('Includeliquidated')}
                />
              </div>
            </Form.Group>
            <SelectField
              name="regMainActivityIdSearch"
              label="ActualMainActivity1"
              lookup={13}
              onChange={this.handleSelectField('regMainActivityId')}
              value={formData.regMainActivityId}
              localize={localize}
            />
            <SelectField
              name="sectorCodeIdSearch"
              label="InstSectorCode"
              lookup={6}
              onChange={this.handleSelectField('sectorCodeId')}
              value={formData.sectorCodeId}
              localize={localize}
            />
            <SelectField
              name="legalFormIdSearch"
              label="LegalForm"
              lookup={5}
              onChange={this.handleSelectField('legalFormId')}
              value={formData.legalFormId}
              localize={localize}
            />
            <SelectField
              name="regionId"
              label="Region"
              lookup={12}
              onChange={this.handleSelectField('regionId')}
              value={formData.regionId}
              localize={localize}
            />
            <br />
          </div>
        )}
        <Button
          content={localize('Search')}
          icon="search"
          labelPosition="left"
          type="submit"
          floated="right"
          primary
        />
        <Button
          onClick={this.onSearchModeToggle}
          content={localize(extended ? 'SearchDefault' : 'SearchExtended')}
          icon={extended ? 'angle double up' : 'angle double down'}
          labelPosition="left"
          type="button"
          floated="right"
        />
      </Form>
    )
  }
}

export default SearchForm
