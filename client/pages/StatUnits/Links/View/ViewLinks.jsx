import React from 'react'
import { func, shape } from 'prop-types'
import { Segment, Header } from 'semantic-ui-react'

import LinksTree from '../components/LinksTree'
import ViewFilter from './ViewFilter'

class ViewLinks extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    findUnit: func.isRequired,
    clear: func.isRequired,
    filter: shape({}),
  }

  static defaultProps = {
    filter: undefined,
  }

  state = {
    filter: undefined,
  }

  componentDidMount() {
    const { filter } = this.props
    if (filter) this.searchUnit(filter)
  }

  componentWillUnmount() {
    this.props.clear()
  }

  searchUnit = ({ type, ...filter }) => {
    this.setState({
      filter: { ...filter, type: type === 'any' ? undefined : type },
    })
  }

  render() {
    const { localize, filter: viewFilter, findUnit } = this.props
    const { filter } = this.state
    return (
      <div>
        <ViewFilter
          isLoading={false}
          value={viewFilter}
          localize={localize}
          onFilter={this.searchUnit}
        />
        <br />
        {filter !== undefined && (
          <Segment>
            <Header as="h4" dividing>
              {localize('SearchResults')}
            </Header>
            <LinksTree filter={filter} getUnitsTree={findUnit} localize={localize} />
          </Segment>
        )}
      </div>
    )
  }
}

export default ViewLinks
