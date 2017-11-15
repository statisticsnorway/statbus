import React from 'react'
import { func, bool, arrayOf, shape, number } from 'prop-types'
import { Icon, Segment, List } from 'semantic-ui-react'
import R from 'ramda'

import Paginate from 'components/Paginate'
import { checkSystemFunction as sF } from 'helpers/config'

class InconsistentRecords extends React.Component {
  static propTypes = {
    localize: func.isRequired,
    logicalCheks: func.isRequired,
    loading: bool,
    inconsistentRecords: arrayOf(shape()),
    totalCount: number,
    query: shape({}).isRequired,
  }

  static defaultProps = {
    loading: true,
    inconsistentRecords: [],
    totalCount: 0,
  }

  componentDidMount() {
    this.props.logicalCheks(this.props.query)
  }

  componentWillReceiveProps(nextProps) {
    if (!R.equals(nextProps.query, this.props.query)) {
      nextProps.logicalCheks(nextProps.query)
    }
  }

  render() {
    const { loading, inconsistentRecords, totalCount, localize } = this.props
    const icons = { 1: 'suitcase', 2: 'briefcase', 3: 'building', 4: 'sitemap' }
    return (
      <div>
        <h2>{localize('AnalyzeRegister')}</h2>
        {sF('StatUnitView') && (
          <Segment loading={loading}>
            <Paginate totalCount={totalCount}>
              <List divided>
                {inconsistentRecords.map(x => (
                  <List.Item key={`${x.type} ${x.regId}`} as="ul">
                    <Icon name={icons[x.type]} />
                    <List.Content>
                      <List.Header>
                        <a href={`statunits/view/${x.type}/${x.regId}`}>{x.name}</a>
                      </List.Header>
                      <List.List as="ul">
                        {x.inconsistents.map(i => (
                          <List.Item as="ul" key={Math.random()}>
                            {localize(i)}
                          </List.Item>
                        ))}
                      </List.List>
                    </List.Content>
                  </List.Item>
                ))}
              </List>
            </Paginate>
          </Segment>
        )}
      </div>
    )
  }
}

export default InconsistentRecords
