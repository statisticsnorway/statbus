import React from 'react'
import { func, shape } from 'prop-types'
import { Segment, Header } from 'semantic-ui-react'

import { wrapper } from 'helpers/locale'
import LinksTree from '../Components/LinksTree'
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
    fetechData: undefined,
  }

  componentDidMount() {
    const { filter } = this.props
    if (filter) this.searchUnit(filter)
  }

  componentWillUnmount() {
    this.props.clear()
  }

  searchUnit = (filter) => {
    const type = filter.type === 'any' ? undefined : filter.type
    this.setState({
      fetechData: () => this.props.findUnit({ ...filter, type }),
    })
  }

  render() {
    const { localize, filter } = this.props
    const { fetechData } = this.state
    return (
      <div>
        <ViewFilter
          isLoading={false}
          value={filter}
          localize={localize}
          onFilter={this.searchUnit}
        />
        <br />
        {fetechData !== undefined &&
          <Segment>
            <Header as="h4" dividing>{localize('SearchResults')}</Header>
            <LinksTree localize={localize} getUnitsTree={fetechData} />
          </Segment>
        }
      </div>
    )
  }
}

export default wrapper(ViewLinks)
