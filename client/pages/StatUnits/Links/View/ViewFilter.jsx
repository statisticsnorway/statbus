import React from 'react'
import { func, shape, string, bool } from 'prop-types'
import { Icon, Form, Button, Popup, Message, Segment } from 'semantic-ui-react'

import Calendar from 'components/Calendar'
import Region from 'components/fields/RegionField'
import { getDate } from 'helpers/dateHelper'
import { statUnitTypes } from 'helpers/enums'
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
    isOpen: false,
    code: null,
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
    this.props.onFilter(this.state.data)
  }

  handleOpen = () => {
    this.setState({ isOpen: true })
  }

  regionSelectedHandler = (region) => {
    this.setState(s => ({ data: { ...s.data, regionCode: region.code } }))
  }

  render() {
    const { localize, isLoading } = this.props
    const { wildcard, lastChangeFrom, lastChangeTo, dataSource, extended } = this.state.data
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
              <Calendar
                key="lastChangeFromKey"
                name="lastChangeFrom"
                value={lastChangeFrom || ''}
                onChange={this.onFieldChanged}
                labelKey="DateOfLastChangeFrom"
                localize={localize}
              />
              <Popup
                trigger={
                  <div className={`field ${styles.items}`}>
                    <Calendar
                      key="lastChangeToKey"
                      name="lastChangeTo"
                      value={lastChangeTo || ''}
                      onChange={this.onFieldChanged}
                      labelKey="DateOfLastChangeTo"
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
                onOpen={this.handleOpen}
              />
            </Form.Group>
            <Form.Group widths="equal">
              <Form.Input
                label={localize('DataSource')}
                name="dataSource"
                value={dataSource || ''}
                onChange={this.onFieldChanged}
              />
            </Form.Group>
            <Segment>
              <Region
                localize={localize}
                onRegionSelected={this.regionSelectedHandler}
                name="regionSelector"
                editing
              />
              <Form.Input
                control={Message}
                name="regionCode"
                label={localize('RegionCode')}
                info
                size="mini"
                onChange={this.onFieldChanged}
                header={this.state.data.regionCode || localize('RegionCode')}
              />
            </Segment>
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
