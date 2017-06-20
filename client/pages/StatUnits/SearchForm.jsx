import React from 'react'
import { Button, Form, Icon } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import statUnitTypes from 'helpers/statUnitTypes'
import Calendar from 'components/Calendar'
import { wrapper } from 'helpers/locale'
import SearchField from 'components/Search/SearchField'
import SearchData from 'components/Search/SearchData'
import styles from './styles'

const { bool, func, number, oneOfType, shape, string } = React.PropTypes

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
    }).isRequired,
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
      dataSource: '',
      regMainActivityId: '',
      sectorCodeId: '',
      legalFormId: '',
    },
    extended: false,
  }

  state = {
    data: this.props.extended,
  }

  onSearchModeToggle = (e) => {
    e.preventDefault()
    this.setState((s) => {
      const isExtended = !s.data.extended
      return { data: { ...s.data, extended: isExtended } }
    })
  }

  setLookupValue = name => (data) => {
    this.props.onChange(name, data.id)
  }

  handleChange = (_, { name, value }) => {
    this.props.onChange(name, value)
  }

  handleChangeCheckbox = (_, { name, checked }) => {
    this.props.onChange(name, checked)
  }

  render() {
    const { formData, localize, onSubmit } = this.props
    const { extended } = this.state.data

    const defaultType = { value: 'any', text: localize('AnyType') }
    const typeOptions = [
      defaultType,
      ...[...statUnitTypes].map(([key, value]) => ({ value: key, text: localize(value) })),
    ]
    const type = typeOptions[Number(formData.type) || 0].value
    const includeLiquidated = formData.includeLiquidated
      && formData.includeLiquidated.toString().toLowerCase() === 'true'

    return (
      <Form onSubmit={onSubmit} className={styles.form}>
        <Form.Group widths="equal">
          <Form.Input
            name="wildcard"
            value={formData.wildcard}
            onChange={this.handleChange}
            label={localize('SearchWildcard')}
            placeholder={localize('Search')}
            size="large"
          />
          <Form.Select
            name="type"
            value={type}
            onChange={this.handleChange}
            options={typeOptions}
            label={localize('StatisticalUnitType')}
            size="large"
            search
          />
        </Form.Group>
        {extended &&
          <div>
            <Form.Group widths="equal">
              {check('Turnover') && <Form.Input
                name="turnoverFrom"
                value={formData.turnoverFrom}
                onChange={this.handleChange}
                label={localize('TurnoverFrom')}
                type="number"
              />}
              {check('Turnover') && <Form.Input
                name="turnoverTo"
                value={formData.turnoverTo}
                onChange={this.handleChange}
                label={localize('TurnoverTo')}
                type="number"
              />}
            </Form.Group>
            <Form.Group widths="equal">
              {check('Employees') && <Form.Input
                name="employeesNumberFrom"
                value={formData.employeesNumberFrom}
                onChange={this.handleChange}
                label={localize('NumberOfEmployeesFrom')}
                type="number"
              />}
              {check('Employees') && <Form.Input
                name="employeesNumberTo"
                value={formData.employeesNumberTo}
                onChange={this.handleChange}
                label={localize('NumberOfEmployeesTo')}
                type="number"
              />}
            </Form.Group>
            <Form.Group widths="equal">
              <Calendar
                key="lastChangeFromKey"
                name="lastChangeFrom"
                value={formData.lastChangeFrom || ''}
                onChange={this.handleChange}
                labelKey="DateOfLastChangeFrom"
                localize={localize}
              />
              <Calendar
                key="lastChangeToKey"
                name="lastChangeTo"
                value={formData.lastChangeTo || ''}
                onChange={this.handleChange}
                labelKey="DateOfLastChangeTo"
                localize={localize}
              />
            </Form.Group>
            <Form.Group widths="equal">
              {check('DataSource') && <Form.Input
                name="dataSource"
                value={formData.dataSource}
                onChange={this.handleChange}
                label={localize('DataSource')}
              />}
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
            <SearchField
              localize={localize}
              searchData={SearchData.activity}
              onValueSelected={this.setLookupValue('regMainActivityId')}
            />
            <SearchField
              localize={localize}
              searchData={SearchData.sectorCode}
              onValueSelected={this.setLookupValue('sectorCodeId')}
            />
            <SearchField
              localize={localize}
              searchData={SearchData.legalForm}
              onValueSelected={this.setLookupValue('legalFormId')}
            />
            <br />
          </div>
        }
        <Button onClick={this.onSearchModeToggle} style={{ cursor: 'pointer' }}>
          <Icon name="search" />
          {localize(extended ? 'SearchDefault' : 'SearchExtended')}
        </Button>
        <Button
          className={styles.sybbtn}
          labelPosition="left"
          icon="search"
          content={localize('Search')}
          type="submit"
          primary
        />
      </Form>
    )
  }
}

export default wrapper(SearchForm)
