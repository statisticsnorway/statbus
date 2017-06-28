import React from 'react'
import { bool, func, number, oneOfType, shape, string } from 'prop-types'
import { Button, Form, Icon, Popup } from 'semantic-ui-react'

import { dataAccessAttribute as check } from 'helpers/checkPermissions'
import statUnitTypes from 'helpers/statUnitTypes'
import Calendar from 'components/Calendar'
import { wrapper } from 'helpers/locale'
import SearchField from 'components/Search/SearchField'
import SearchData from 'components/Search/SearchData'
import { getDate } from 'helpers/dateHelper'
import styles from './styles.pcss'

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
    selected: {
      regMainActivityId: '',
      sectorCodeId: '',
      legalFormId: '',
    },
    isOpen: false,
  }

  onSearchModeToggle = (e) => {
    e.preventDefault()
    this.setState((s) => {
      const isExtended = !s.data.extended
      return { data: { ...s.data, extended: isExtended } }
    })
  }

  onValueChanged = name => (value) => {
    this.setState(s => ({ selected: { ...s.selected, [name]: value === undefined ? '' : value } }))
  }

  setLookupValue = name => (data) => {
    this.setState(s => ({ selected: { ...s.selected, [name]: data.name } }))

    this.props.onChange(name, data.id)
  }

  handleChange = (_, { name, value }) => {
    this.props.onChange(name, value)
  }

  handleChangeCheckbox = (_, { name, checked }) => {
    this.props.onChange(name, checked)
  }

  handleOpen = () => {
    this.setState({ isOpen: true })
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

    const regMainActivitySearchData = { ...SearchData.activity,
      data: { ...SearchData.activity.data,
        id: formData.regMainActivityId,
        name: this.state.selected.regMainActivityId } }

    const sectorCodeSearchData = { ...SearchData.sectorCode,
      data: { ...SearchData.sectorCode.data,
        id: formData.sectorCodeId,
        name: this.state.selected.sectorCodeId } }

    const legalFormSearchData = { ...SearchData.legalForm,
      data: { ...SearchData.legalForm.data,
        id: formData.legalFormId,
        name: this.state.selected.legalFormId } }

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
                min={0}
              />}
              {check('Turnover') && <Form.Input
                name="turnoverTo"
                value={formData.turnoverTo}
                onChange={this.handleChange}
                label={localize('TurnoverTo')}
                type="number"
                min={0}
              />}
            </Form.Group>
            <Form.Group widths="equal">
              {check('Employees') && <Form.Input
                name="employeesNumberFrom"
                value={formData.employeesNumberFrom}
                onChange={this.handleChange}
                label={localize('NumberOfEmployeesFrom')}
                type="number"
                min={0}
              />}
              {check('Employees') && <Form.Input
                name="employeesNumberTo"
                value={formData.employeesNumberTo}
                onChange={this.handleChange}
                label={localize('NumberOfEmployeesTo')}
                type="number"
                min={0}
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
              <Popup
                trigger={
                  <div className={`field ${styles.items}`}>
                    <Calendar
                      key="lastChangeToKey"
                      name="lastChangeTo"
                      value={formData.lastChangeTo || ''}
                      onChange={this.handleChange}
                      labelKey="DateOfLastChangeTo"
                      localize={localize}
                      error={getDate(formData.lastChangeFrom) > getDate(formData.lastChangeTo)}
                    />
                  </div>
                }
                content={`"${localize('DateOfLastChangeTo')}" ${localize('CantBeLessThan')} "${localize('DateOfLastChangeFrom')}"`}
                open={getDate(formData.lastChangeFrom) > getDate(formData.lastChangeTo)}
                onOpen={this.handleOpen}
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
              key="regMainActivityIdSearch"
              localize={localize}
              searchData={regMainActivitySearchData}
              onValueChanged={this.onValueChanged('regMainActivityId')}
              onValueSelected={this.setLookupValue('regMainActivityId')}
            />
            <SearchField
              key="sectorCodeIdSearch"
              localize={localize}
              searchData={sectorCodeSearchData}
              onValueChanged={this.onValueChanged('sectorCodeId')}
              onValueSelected={this.setLookupValue('sectorCodeId')}
            />
            <SearchField
              key="legalFormIdSearch"
              localize={localize}
              searchData={legalFormSearchData}
              onValueChanged={this.onValueChanged('legalFormId')}
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
