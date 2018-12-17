import React from 'react'
import { func, shape, string, bool } from 'prop-types'
import { Icon, Form, Button, Popup } from 'semantic-ui-react'
import Select from 'react-select'
import debounce from 'lodash/debounce'

import { DateTimeField, RegionField } from 'components/fields'
import { getDate } from 'helpers/dateHelper'
import { statUnitTypes } from 'helpers/enums'
import { getNewName } from 'helpers/locale'
import { internalRequest } from 'helpers/request'
import { NameCodeOption, notSelected } from 'components/fields/SelectField'
import styles from './styles.pcss'

const types = [['any', 'AnyType'], ...statUnitTypes]

class ViewFilter extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    isLoading: bool,
    onFilter: func.isRequired,
    value: shape({
      name: string,
    }),
  }

  static defaultProps = {
    value: {
      name: '',
      extended: false,
    },
    isLoading: false,
  }

  state = {
    data: this.props.value,
    dataSources: [],
    regions: [],
  }

  componentWillReceiveProps(nextProps) {
    const { dataSources, regions, data, data: { dataSource, regionCode } } = this.state
    if (nextProps.locale !== this.props.locale) {
      this.setState({
        dataSources: dataSources.map(NameCodeOption.transform),
        regions: regions.map(NameCodeOption.transform),
        data: {
          ...data,
          dataSource: dataSource && NameCodeOption.transform(dataSource),
          regionCode: regionCode && NameCodeOption.transform(regionCode),
        },
      })
    }
  }

  componentDidMount() {
    fetch('/api/lookup/paginated/7?page=0&pageSize=10', {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'same-origin',
    })
      .then(resp => resp.json())
      .then((result) => {
        const options =
          Array.isArray(result) && result.length > 0 ? result.map(NameCodeOption.transform) : []
        this.setState({ dataSources: options })
      })
  }

  onFieldChanged = (e, { name, value }) => {
    this.setState(s => ({
      data: {
        ...s.data,
        [name]: value,
      },
    }))
  }

  onSearchModeToggle = (e) => {
    e.preventDefault()
    this.setState((s) => {
      const isExtended = !s.data.extended
      return isExtended
        ? { data: { ...s.data, extended: isExtended } }
        : { data: { source: s.data.source, name: s.data.name, extended: isExtended } }
    })
  }

  handleSubmit = (e) => {
    e.preventDefault()
    const { dataSource, regionCode } = this.state.data
    const data = {
      ...this.state.data,
      dataSource: dataSource && dataSource.value,
      regionCode: regionCode && regionCode.value,
    }
    this.props.onFilter(data)
  }

  loadOptions = (wildcard, page, callback) => {
    internalRequest({
      url: `/api/lookup/paginated/${12}`,
      queryParams: { page: page - 1, pageSize: 10, wildcard },
      method: 'get',
      onSuccess: (result) => {
        const regions =
          Array.isArray(result) && result.length > 0 ? result.map(NameCodeOption.transform) : []
        this.setState({ regions: this.state.regions.concat(result) }, () => {
          callback(null, { options: regions })
        })
      },
    })
  }

  handleLoadOptions = debounce(this.loadOptions, 350)

  selectHandler = (data, name) => {
    const value = data || ''
    this.setState(prevState => ({ data: { ...prevState.data, [name]: value } }))
  }

  render() {
    const { localize, isLoading } = this.props
    const {
      wildcard,
      lastChangeFrom,
      lastChangeTo,
      dataSource,
      regionCode,
      extended,
    } = this.state.data
    const typeOptions = types.map(kv => ({ value: kv[0], text: localize(kv[1]) }))
    const type = typeOptions[Number(this.state.data.type) || 0].value
    return (
      <Form onSubmit={this.handleSubmit} loading={isLoading}>
        <Form.Group widths="equal">
          <Form.Input
            name="wildcard"
            value={wildcard}
            onChange={this.onFieldChanged}
            label={localize('SearchWildcard')}
            placeholder={localize('Search')}
            size="large"
          />
          <Form.Select
            name="type"
            value={type}
            onChange={this.onFieldChanged}
            options={typeOptions}
            label={localize('StatisticalUnitType')}
            size="large"
            search
          />
        </Form.Group>
        {extended && (
          <div>
            <Form.Group widths="equal">
              <DateTimeField
                name="lastChangeFrom"
                value={lastChangeFrom || ''}
                onChange={this.onFieldChanged}
                label="DateOfLastChangeFrom"
                localize={localize}
              />
              <Popup
                trigger={
                  <div className={`field ${styles.items}`}>
                    <DateTimeField
                      name="lastChangeTo"
                      value={lastChangeTo || ''}
                      onChange={this.onFieldChanged}
                      label="DateOfLastChangeTo"
                      localize={localize}
                      error={
                        getDate(lastChangeFrom) > getDate(lastChangeTo) &&
                        (lastChangeTo !== undefined || lastChangeTo !== '')
                      }
                    />
                  </div>
                }
                content={`"${localize('DateOfLastChangeTo')}" ${localize('CantBeLessThan')} "${localize('DateOfLastChangeFrom')}"`}
                open={
                  getDate(lastChangeFrom) > getDate(lastChangeTo) &&
                  (lastChangeTo !== undefined || lastChangeTo !== '')
                }
              />
            </Form.Group>
            <label className={styles.label}>{localize('DataSource')}</label>
            <Select
              value={dataSource || ''}
              options={this.state.dataSources}
              optionRenderer={NameCodeOption.render}
              onChange={data => this.selectHandler(data, 'dataSource')}
              openOnFocus
              placeholder={localize('DataSource')}
              inputProps={{ type: 'react-select' }}
            />
            <br />
            <label className={styles.label}>{localize('Region')}</label>
            <Select.Async
              value={regionCode || ''}
              loadOptions={this.handleLoadOptions}
              options={this.state.regions}
              optionRenderer={NameCodeOption.render}
              onChange={data => this.selectHandler(data, 'regionCode')}
              pagination
              searchable
              openOnFocus
              placeholder={localize('Region')}
              inputProps={{ type: 'react-select' }}
            />
            <br />
          </div>
        )}
        <Button onClick={this.onSearchModeToggle} style={{ cursor: 'pointer' }}>
          <Icon name="search" />
          {localize(extended ? 'SearchDefault' : 'SearchExtended')}
        </Button>
        <Button color="blue" floated="right">
          {localize('Search')}
        </Button>
      </Form>
    )
  }
}

export default ViewFilter
